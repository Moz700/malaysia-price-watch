/* =====================================================================
   q20 · Running cumulative price change since October 2025, per item
   ---------------------------------------------------------------------
   Stakeholder : C. Procurement / supply chain analyst
   Question    : By each month, how far has each item's price moved since
                 October 2025?
   Method      : Monthly median per item (q17 method). Month-on-month
                 changes cannot be added: +10% then -10% is not 0%
                 (100 -> 110 -> 99). Adding logarithms gives the exact result:
                     cumulative = EXP( SUM( LN(this month / last month) ) ) - 1
                 The query also computes the direct answer (this month /
                 October - 1) as a cross-check.
   Answer      : Since Oct 2025: chicken +9.4%, grade B eggs +10.1%
                 (after -24.5% in April), red chilli +6.3%, imported rice
                 -8.3%, sugar and packet oil 0.0%. Chained log changes
                 equal the direct comparison every month.
   ===================================================================== */

WITH premise_month AS (
    SELECT item_code, premise_code, month, price AS p      -- one price per shop per month
    FROM core.fact_premise_item_month
),
item_month AS (
    SELECT item_code, month, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p) AS median_price
    FROM premise_month GROUP BY item_code, month
),
log_change AS (
    SELECT item_code, month, median_price,
           LN(median_price / LAG(median_price) OVER (PARTITION BY item_code ORDER BY month)) AS ln_mom,
           FIRST_VALUE(median_price) OVER (PARTITION BY item_code ORDER BY month) AS oct_price
    FROM item_month
),
running AS (
    SELECT item_code, month, median_price, oct_price,
           EXP(SUM(COALESCE(ln_mom, 0)) OVER (PARTITION BY item_code ORDER BY month)) - 1 AS cum_change_running,
           median_price / oct_price - 1                                                      AS cum_change_direct
    FROM log_change
)
SELECT i.item, r.month,
       ROUND(r.median_price::numeric, 2)             AS median_rm,
       ROUND((r.cum_change_running * 100)::numeric, 1) AS cum_change_pct_running,
       ROUND((r.cum_change_direct  * 100)::numeric, 1) AS cum_change_pct_direct
FROM running AS r
JOIN core.dim_item AS i ON i.item_code = r.item_code
WHERE r.item_code IN (2066, 1, 1110, 918, 1589, 93)
ORDER BY i.item, r.month;
