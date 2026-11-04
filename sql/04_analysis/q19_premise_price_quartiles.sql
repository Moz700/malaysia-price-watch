/* =====================================================================
   q19 · Split premises into price quartiles within each state
   ---------------------------------------------------------------------
   Stakeholder : A. Consumer and policy analyst (KPDN)
   Question    : In each state, which shops sit in the cheapest quarter and
                 which in the dearest, and what kinds of shop are they?
   Method      : September 2026 premise price index (q11 method, 30+ items).
                 NTILE(4) OVER (PARTITION BY state ORDER BY index) cuts each
                 state's shops into 4 equal-sized groups: 1 = cheapest 25%.
   Answer      : 54.7% of hypermarkets sit in their state's cheapest
                 quarter and 8.7% in the dearest; for wet markets it is
                 9.9% and 49.5%.
   ===================================================================== */

DROP TABLE IF EXISTS premise_quartile;
CREATE TEMP TABLE premise_quartile AS
WITH sep AS (
    SELECT premise_code, item_code, price
    FROM core.fact_premise_item_month
    WHERE month = DATE '2026-09-01'
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep GROUP BY item_code
),
premise_index AS (
    SELECT s.premise_code, AVG(s.price / n.nat_median) * 100 AS price_index
    FROM sep AS s JOIN national AS n ON n.item_code = s.item_code
    GROUP BY s.premise_code HAVING COUNT(*) >= 30
)
SELECT x.premise_code, p.state, p.premise_type_en, x.price_index,
       NTILE(4) OVER (PARTITION BY p.state ORDER BY x.price_index) AS price_quartile
FROM premise_index    AS x
JOIN core.dim_premise AS p ON p.premise_code = x.premise_code;

-- 19a. Index range of each quartile, per state
SELECT state, price_quartile,
       COUNT(*)                               AS premises,
       ROUND(MIN(price_index)::numeric, 1)    AS from_index,
       ROUND(MAX(price_index)::numeric, 1)    AS to_index
FROM premise_quartile
GROUP BY state, price_quartile
ORDER BY state, price_quartile;

-- 19b. Who lives in the cheapest and dearest quartiles? (all states pooled)
SELECT
    premise_type_en,
    COUNT(*)                                                                           AS premises,
    ROUND(100.0 * COUNT(*) FILTER (WHERE price_quartile = 1) / COUNT(*), 1)            AS pct_in_cheapest_q,
    ROUND(100.0 * COUNT(*) FILTER (WHERE price_quartile = 4) / COUNT(*), 1)            AS pct_in_dearest_q
FROM premise_quartile
GROUP BY premise_type_en
ORDER BY pct_in_cheapest_q DESC;
