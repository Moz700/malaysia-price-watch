/* =====================================================================
   q29 · Which items have the most stable prices?
   ---------------------------------------------------------------------
   Stakeholder : C. Procurement / supply chain analyst
   Question    : Which items barely move over the year (easy to budget),
                 and which swing the most (need hedging or flexible
                 contracts)?
   Method      : Monthly median per item (q17 method), items with 50+ shops
                 in every one of the 12 months. Coefficient of variation
                 over the 12 months = STDDEV / AVG. Lowest = most stable.
   Answer      : Most stable: price-controlled or list-priced items
                 (packet cooking oil, infant formula, soy sauce) with
                 zero monthly variation. Least stable: red chilli (cili
                 akar merah, CV 33.4%, RM 13.99-32.00) and Indian rose
                 shallots (32.3%).
   ===================================================================== */

DROP TABLE IF EXISTS item_stability;
CREATE TEMP TABLE item_stability AS
WITH premise_month AS (
    SELECT item_code, premise_code, month, price AS p      -- one price per shop per month
    FROM core.fact_premise_item_month
),
item_month AS (
    SELECT item_code, month, COUNT(*) AS premises,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p) AS median_price
    FROM premise_month GROUP BY item_code, month
)
SELECT item_code,
       COUNT(*)                                  AS months,
       MIN(median_price)                         AS low,
       MAX(median_price)                         AS high,
       STDDEV(median_price) / AVG(median_price)  AS cv
FROM item_month
GROUP BY item_code
HAVING COUNT(*) = 12 AND MIN(premises) >= 50;

-- 29a. The 15 most stable
SELECT i.item, i.unit, i.item_category,
       ROUND(s.low::numeric, 2) AS lowest_monthly_median_rm,
       ROUND(s.high::numeric, 2) AS highest_monthly_median_rm,
       ROUND((s.cv * 100)::numeric, 2) AS cv_pct
FROM item_stability AS s JOIN core.dim_item AS i ON i.item_code = s.item_code
ORDER BY s.cv
LIMIT 15;

-- 29b. The 10 least stable
SELECT i.item, i.unit, i.item_category,
       ROUND(s.low::numeric, 2) AS lowest_monthly_median_rm,
       ROUND(s.high::numeric, 2) AS highest_monthly_median_rm,
       ROUND((s.cv * 100)::numeric, 2) AS cv_pct
FROM item_stability AS s JOIN core.dim_item AS i ON i.item_code = s.item_code
ORDER BY s.cv DESC
LIMIT 10;

-- 29c. Stability by item group
SELECT i.item_group_en,
       COUNT(*)                                             AS items,
       ROUND((AVG(s.cv) * 100)::numeric, 2)                 AS avg_cv_pct,
       COUNT(*) FILTER (WHERE s.cv = 0)                     AS items_with_no_change_at_all
FROM item_stability AS s JOIN core.dim_item AS i ON i.item_code = s.item_code
GROUP BY i.item_group_en
ORDER BY avg_cv_pct;
