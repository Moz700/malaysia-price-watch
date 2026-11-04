/* =====================================================================
   q25 · First and latest price per premise and item over the year
   ---------------------------------------------------------------------
   Stakeholder : B. Retail category manager
   Question    : Comparing each shop's first price on an item with its
                 latest, how many ended the year higher, the same, or
                 lower, and does that differ by format?
   Method      : core.fact_premise_item_month (one price per shop, item and
                 month: the median of that month's reports, so a one-day
                 promotion cannot decide the answer). For each (premise,
                 item) series, FIRST_VALUE and LAST_VALUE fetch the first and
                 last month and their prices. Only series that start in
                 Oct 2025 and end in Sep 2026, so every series covers the
                 full year.
                 Note: with ORDER BY, the default window frame stops at the
                 CURRENT row, so LAST_VALUE would just return the current
                 row's price. The frame must be widened to the whole
                 partition: ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED
                 FOLLOWING.
   Why the monthly table: on the 20.7M-row daily table the planner chose
                 to walk the premise index row by row (random reads) and the
                 query ran for over 10 minutes; on the 2.85M-row monthly
                 table it takes seconds.
   Answer      : Of 202,018 full-year series, 30.5% ended higher, 45.2%
                 the same, 24.3% lower. Sundry shops held prices most
                 (57.5% unchanged); fresh produce ended higher in 44.2%
                 of series, packaged goods in 16.7%.
   ===================================================================== */

DROP TABLE IF EXISTS first_last;
CREATE TEMP TABLE first_last AS
SELECT premise_code, item_code, first_month, first_price, last_month, last_price
FROM (
    SELECT
        premise_code, item_code,
        FIRST_VALUE(month) OVER w AS first_month,
        FIRST_VALUE(price) OVER w AS first_price,
        LAST_VALUE(month)  OVER w AS last_month,
        LAST_VALUE(price)  OVER w AS last_price,
        ROW_NUMBER()       OVER w AS rn
    FROM core.fact_premise_item_month
    WINDOW w AS (PARTITION BY premise_code, item_code ORDER BY month
                 ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
) AS t
WHERE rn = 1;              -- keep one row per (premise, item)

-- 25a. Full-year series: higher, same or lower at the end?
SELECT p.premise_type_en,
       COUNT(*)                                                                         AS series,
       ROUND(100.0 * AVG(CASE WHEN fl.last_price > fl.first_price THEN 1 ELSE 0 END), 1) AS pct_higher,
       ROUND(100.0 * AVG(CASE WHEN fl.last_price = fl.first_price THEN 1 ELSE 0 END), 1) AS pct_same,
       ROUND(100.0 * AVG(CASE WHEN fl.last_price < fl.first_price THEN 1 ELSE 0 END), 1) AS pct_lower,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY fl.last_price / fl.first_price - 1) * 100)::numeric, 1) AS median_change_pct
FROM first_last       AS fl
JOIN core.dim_premise AS p ON p.premise_code = fl.premise_code
WHERE fl.first_month = DATE '2025-10-01' AND fl.last_month = DATE '2026-09-01'
GROUP BY ROLLUP (p.premise_type_en)             -- ROLLUP adds an all-types total row (NULL label)
ORDER BY p.premise_type_en NULLS LAST;

-- 25b. By item group: where did shops most often end the year dearer?
SELECT i.item_group_en,
       COUNT(*)                                                                         AS series,
       ROUND(100.0 * AVG(CASE WHEN fl.last_price > fl.first_price THEN 1 ELSE 0 END), 1) AS pct_higher,
       ROUND(100.0 * AVG(CASE WHEN fl.last_price < fl.first_price THEN 1 ELSE 0 END), 1) AS pct_lower
FROM first_last    AS fl
JOIN core.dim_item AS i ON i.item_code = fl.item_code
WHERE fl.first_month = DATE '2025-10-01' AND fl.last_month = DATE '2026-09-01'
GROUP BY i.item_group_en
ORDER BY pct_higher DESC;

-- 25c. Example rows for one shop
SELECT i.item, fl.first_month, fl.first_price, fl.last_month, fl.last_price
FROM first_last    AS fl
JOIN core.dim_item AS i ON i.item_code = fl.item_code
WHERE fl.premise_code = 5274
ORDER BY i.item
LIMIT 15;
