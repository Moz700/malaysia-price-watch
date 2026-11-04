/* =====================================================================
   core.fact_premise_item_month: one value per shop, item, month
   ---------------------------------------------------------------------
   Shops do not report equally often. Prices reported per item per
   month, September 2026:
       wet markets            ~15
       supermarkets           ~8
       hypermarkets           ~8
       mini markets           ~3
       sundry shops           ~3
   A median taken straight over the raw rows therefore lets wet markets
   and supermarkets "vote" 2-5 times more than mini markets and sundry
   shops. Checked on September 2026: the raw-row median differed from the
   one-shop-one-vote median for 123 of 329 items, by more than 5% for 25
   of them (up to 25.6%).

   This aggregate fact table gives each shop one price per item per
   month (the median of its own reports). Every analysis that compares
   prices across shops uses it, so each shop counts once.
   It is also ~8x smaller than fact_price, so those queries run faster.

   Grain: one row per (month, premise, item).
   Runtime on the build machine: about 2 minutes.
   ===================================================================== */

DROP TABLE IF EXISTS core.fact_premise_item_month CASCADE;

CREATE TABLE core.fact_premise_item_month AS
SELECT
    DATE_TRUNC('month', date)::date                                           AS month,
    premise_code,
    item_code,
    COUNT(*)                                                                  AS n_reports,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price)::numeric, 2)     AS price,       -- shop's typical price that month
    ROUND(AVG(price), 4)                                                      AS avg_price,
    MIN(price)                                                                AS min_price,
    MAX(price)                                                                AS max_price
FROM core.fact_price
GROUP BY DATE_TRUNC('month', date), premise_code, item_code;

ALTER TABLE core.fact_premise_item_month
    ADD CONSTRAINT pk_fpim         PRIMARY KEY (month, premise_code, item_code),
    ADD CONSTRAINT fk_fpim_premise FOREIGN KEY (premise_code) REFERENCES core.dim_premise (premise_code),
    ADD CONSTRAINT fk_fpim_item    FOREIGN KEY (item_code)    REFERENCES core.dim_item (item_code);

CREATE INDEX idx_fpim_item ON core.fact_premise_item_month (item_code, month);
ANALYZE core.fact_premise_item_month;

-- Check: rows per month, and reports per shop-item by premise type
SELECT month, COUNT(*) AS shop_item_rows, SUM(n_reports) AS raw_rows
FROM core.fact_premise_item_month
GROUP BY month
ORDER BY month;

SELECT p.premise_type_en,
       ROUND(AVG(m.n_reports), 1) AS avg_reports_per_shop_item_month
FROM core.fact_premise_item_month AS m
JOIN core.dim_premise AS p ON p.premise_code = m.premise_code
WHERE m.month = DATE '2026-09-01'
GROUP BY p.premise_type_en
ORDER BY avg_reports_per_shop_item_month DESC;

-- The national median per item, September 2026, computed two ways.
--   raw-row median   : every daily report counts (frequent reporters outvote others)
--   one shop one vote: each shop's monthly price counts once
WITH sep_rows AS (
    SELECT item_code, price
    FROM core.fact_price
    WHERE date >= DATE '2026-09-01' AND date < DATE '2026-10-01'
),
row_median AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS m
    FROM sep_rows GROUP BY item_code
),
shop_median AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS m
    FROM core.fact_premise_item_month
    WHERE month = DATE '2026-09-01'
    GROUP BY item_code
)
SELECT
    COUNT(*)                                                  AS items,
    COUNT(*) FILTER (WHERE r.m <> s.m)                        AS items_where_medians_differ,
    COUNT(*) FILTER (WHERE ABS(r.m / s.m - 1) > 0.05)         AS items_differ_by_over_5pct,
    ROUND((MAX(ABS(r.m / s.m - 1)) * 100)::numeric, 1)        AS largest_difference_pct
FROM row_median  AS r
JOIN shop_median AS s ON s.item_code = r.item_code;
