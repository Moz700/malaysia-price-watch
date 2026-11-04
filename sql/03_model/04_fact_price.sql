/* =====================================================================
   core.fact_price: the cleaned fact table
   ---------------------------------------------------------------------
   Measure: price.
   Grain: one row per (date, premise, item).

   The quality rules from sql/02_quality are applied in order, and every
   removed row is counted once in core.data_quality_log:
     1  price NULL or below RM 0.10              -> drop
     4  item_code not in dim_item                -> drop
     5  premise_code not in dim_premise          -> drop
     2+3 duplicates / conflicting prices          -> collapse to one row (median)
     6  price > 5x or < 0.2x item-month median   -> drop
        (full-year median if the item has < 20 reports that month)
     7  late joiners / early leavers             -> keep, flag in dim_premise

   Load order: create the table without keys, insert 20 million rows,
   then add the primary and foreign keys. Checking keys once at the end is
   far faster than checking them row by row during the insert.

   Runtime on the build machine: about 4 minutes.
   ===================================================================== */

-- Step 1. Rows that pass checks 1, 4 and 5, collapsed to one row per
--         (date, premise, item). PERCENTILE_CONT(0.5) = median; with one
--         row per group it just returns that row's price.
DROP TABLE IF EXISTS staging.price_step1;
CREATE TABLE staging.price_step1 AS
SELECT
    r.date,
    r.premise_code,
    r.item_code,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.price)::numeric, 2) AS price
FROM staging.raw_price AS r
WHERE r.price >= 0.10                                                              -- check 1
  AND EXISTS (SELECT 1 FROM core.dim_item    AS i WHERE i.item_code    = r.item_code)    -- check 4
  AND EXISTS (SELECT 1 FROM core.dim_premise AS p WHERE p.premise_code = r.premise_code) -- check 5
GROUP BY r.date, r.premise_code, r.item_code;                                      -- checks 2+3

-- Step 2. The yardstick for check 6: the item's national median for the
--         month. If an item has fewer than 20 reports in a month, one odd
--         price can itself be the median (e.g. a single RM 0.01 report), so for
--         those thin months the item's full-year median is used instead.
DROP TABLE IF EXISTS staging.item_month_median;
CREATE TABLE staging.item_month_median AS
WITH monthly AS (
    SELECT item_code,
           DATE_TRUNC('month', date)::date                      AS month,
           COUNT(*)                                             AS n,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price)   AS month_median
    FROM staging.price_step1
    GROUP BY item_code, DATE_TRUNC('month', date)
),
yearly AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS year_median
    FROM staging.price_step1
    GROUP BY item_code
)
SELECT m.item_code,
       m.month,
       CASE WHEN m.n >= 20 THEN m.month_median ELSE y.year_median END AS median_price
FROM monthly AS m
JOIN yearly  AS y ON y.item_code = m.item_code;

-- Step 3. Create the fact table and insert rows that pass check 6
DROP TABLE IF EXISTS core.fact_price CASCADE;
CREATE TABLE core.fact_price (
    date          DATE          NOT NULL,
    premise_code  INTEGER       NOT NULL,
    item_code     INTEGER       NOT NULL,
    price         NUMERIC(10,2) NOT NULL CHECK (price > 0)
);

INSERT INTO core.fact_price (date, premise_code, item_code, price)
SELECT s.date, s.premise_code, s.item_code, s.price
FROM staging.price_step1 AS s
JOIN staging.item_month_median AS m
  ON m.item_code = s.item_code
 AND m.month     = DATE_TRUNC('month', s.date)::date
WHERE s.price BETWEEN 0.2 * m.median_price AND 5 * m.median_price             -- check 6
ORDER BY s.item_code, s.date;   -- store rows of the same item together (helps later scans)

-- Step 4. Keys, added after the load
ALTER TABLE core.fact_price
    ADD CONSTRAINT pk_fact_price      PRIMARY KEY (date, premise_code, item_code),
    ADD CONSTRAINT fk_fact_date       FOREIGN KEY (date)         REFERENCES core.dim_date (date),
    ADD CONSTRAINT fk_fact_premise    FOREIGN KEY (premise_code) REFERENCES core.dim_premise (premise_code),
    ADD CONSTRAINT fk_fact_item       FOREIGN KEY (item_code)    REFERENCES core.dim_item (item_code);

ANALYZE core.fact_price;

-- Step 5. Quality check 7: reporting span per premise, written into dim_premise
UPDATE core.dim_premise AS p
SET first_seen        = s.first_seen,
    last_seen         = s.last_seen,
    days_reported     = s.days_reported,
    reporting_pattern = CASE
        WHEN s.first_seen <  DATE '2025-11-01' AND s.last_seen >= DATE '2026-09-01' THEN 'Full year'
        WHEN s.first_seen >= DATE '2025-11-01' AND s.last_seen >= DATE '2026-09-01' THEN 'Joined late'
        WHEN s.first_seen <  DATE '2025-11-01' AND s.last_seen <  DATE '2026-09-01' THEN 'Stopped early'
        ELSE 'Joined late, stopped early'
    END
FROM (
    SELECT premise_code,
           MIN(date)            AS first_seen,
           MAX(date)            AS last_seen,
           COUNT(DISTINCT date) AS days_reported
    FROM core.fact_price
    GROUP BY premise_code
) AS s
WHERE s.premise_code = p.premise_code;

UPDATE core.dim_premise
SET reporting_pattern = 'No prices in period'
WHERE reporting_pattern IS NULL;

-- Step 6. Quality log: each removed row counted under exactly one check
DROP TABLE IF EXISTS core.data_quality_log;
CREATE TABLE core.data_quality_log (
    step         SMALLINT PRIMARY KEY,
    check_name   TEXT,
    rows         BIGINT,
    action       TEXT
);

INSERT INTO core.data_quality_log
WITH counts AS (
    SELECT
        (SELECT COUNT(*) FROM staging.raw_price)                                   AS rows_in,
        (SELECT COUNT(*) FROM staging.raw_price WHERE price IS NULL OR price < 0.10) AS c1,
        (SELECT COUNT(*) FROM staging.raw_price AS r
          WHERE r.price >= 0.10
            AND NOT EXISTS (SELECT 1 FROM core.dim_item i WHERE i.item_code = r.item_code)) AS c4,
        (SELECT COUNT(*) FROM staging.raw_price AS r
          WHERE r.price >= 0.10
            AND EXISTS     (SELECT 1 FROM core.dim_item    i WHERE i.item_code    = r.item_code)
            AND NOT EXISTS (SELECT 1 FROM core.dim_premise p WHERE p.premise_code = r.premise_code)) AS c5,
        (SELECT COUNT(*) FROM staging.price_step1)                                 AS step1_rows,
        (SELECT COUNT(*) FROM core.fact_price)                                     AS rows_out
)
SELECT * FROM (VALUES
    (0, 'Rows loaded into staging',                        (SELECT rows_in FROM counts), 'start'),
    (1, 'Price missing or below RM 0.10',                  (SELECT c1 FROM counts),      'dropped'),
    (4, 'Item code not in lookup_item',                    (SELECT c4 FROM counts),      'dropped'),
    (5, 'Premise code not in lookup_premise',              (SELECT c5 FROM counts),      'dropped'),
    (2, 'Duplicate / conflicting prices (same day, shop, item)',
        (SELECT rows_in - c1 - c4 - c5 - step1_rows FROM counts),                         'collapsed to median'),
    (6, 'Outlier: >5x or <1/5 of item median for the month',       (SELECT step1_rows - rows_out FROM counts), 'dropped'),
    (9, 'Rows in core.fact_price',                         (SELECT rows_out FROM counts), 'final')
) AS v(step, check_name, rows, action);

-- Quality log summary
SELECT
    step, check_name, rows, action,
    ROUND(100.0 * rows / (SELECT rows FROM core.data_quality_log WHERE step = 0), 3) AS pct_of_loaded
FROM core.data_quality_log
ORDER BY CASE step WHEN 0 THEN 0 WHEN 9 THEN 99 ELSE step END;

-- Total removed, as one number
SELECT
    (SELECT rows FROM core.data_quality_log WHERE step = 0)
  - (SELECT rows FROM core.data_quality_log WHERE step = 9)                       AS rows_removed,
    ROUND(100.0 * (1 - (SELECT rows FROM core.data_quality_log WHERE step = 9)::numeric
                     / (SELECT rows FROM core.data_quality_log WHERE step = 0)), 2) AS pct_removed;
