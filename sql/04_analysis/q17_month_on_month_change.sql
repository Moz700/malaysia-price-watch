/* =====================================================================
   q17 · Month-on-month median price change for each item
   ---------------------------------------------------------------------
   Stakeholder : C. Procurement / supply chain analyst
   Question    : How does each item's typical price move month to month,
                 and which months saw the sharpest jumps?
   Method      : 1) each shop's price for an item in a month
                    (core.fact_premise_item_month)
                 2) the item's monthly median across shops (each shop counts
                    once, however often it reports)
                 3) LAG() fetches the previous month's median on the same
                    item, so change = this month / last month - 1
   Answer      : Biggest monthly jumps: seedless watermelon +85.4% (Jun
                 2026), red chilli (cili akar merah) +65.7% and pak choy
                 +50.0% (Dec 2025). Fresh produce moves 4.94% a month on
                 average vs 0.55% for packaged goods.
   ===================================================================== */

DROP TABLE IF EXISTS item_month;
CREATE TEMP TABLE item_month AS
WITH premise_month AS (                                                   -- step 1
    SELECT item_code, premise_code, month, price AS p      -- one price per shop per month
    FROM core.fact_premise_item_month
)
SELECT item_code, month,
       COUNT(*)                                            AS premises,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p)      AS median_price   -- step 2
FROM premise_month
GROUP BY item_code, month;

-- 17a. The month-on-month table for five staples
SELECT
    i.item,
    m.month,
    ROUND(m.median_price::numeric, 2)                                                    AS median_rm,
    ROUND(LAG(m.median_price) OVER w::numeric, 2)                                        AS prev_month_rm,   -- step 3
    ROUND(((m.median_price / LAG(m.median_price) OVER w - 1) * 100)::numeric, 1)         AS mom_change_pct
FROM item_month    AS m
JOIN core.dim_item AS i ON i.item_code = m.item_code
WHERE m.item_code IN (2066, 1, 1110, 918, 1589, 93)
WINDOW w AS (PARTITION BY m.item_code ORDER BY m.month)
ORDER BY i.item, m.month;

-- 17b. The 10 biggest single-month moves (items with 50+ shops that month)
WITH mom AS (
    SELECT item_code, month, premises, median_price,
           median_price / LAG(median_price) OVER (PARTITION BY item_code ORDER BY month) - 1 AS mom
    FROM item_month
)
SELECT i.item, i.unit, m.month, m.premises,
       ROUND(m.median_price::numeric, 2)  AS median_rm,
       ROUND((m.mom * 100)::numeric, 1)   AS mom_change_pct
FROM mom AS m JOIN core.dim_item AS i ON i.item_code = m.item_code
WHERE m.mom IS NOT NULL AND m.premises >= 50
ORDER BY ABS(m.mom) DESC
LIMIT 10;

-- 17c. Which item groups are most volatile month to month?
WITH mom AS (
    SELECT item_code, premises,
           median_price / LAG(median_price) OVER (PARTITION BY item_code ORDER BY month) - 1 AS mom
    FROM item_month
)
SELECT i.item_group_en,
       COUNT(DISTINCT m.item_code)                       AS items,
       ROUND(AVG(ABS(m.mom))::numeric * 100, 2)          AS avg_abs_mom_change_pct,
       ROUND(100.0 * AVG(CASE WHEN m.mom = 0 THEN 1 ELSE 0 END), 1) AS pct_months_no_change
FROM mom AS m JOIN core.dim_item AS i ON i.item_code = m.item_code
WHERE m.mom IS NOT NULL AND m.premises >= 50
GROUP BY i.item_group_en
ORDER BY avg_abs_mom_change_pct DESC;
