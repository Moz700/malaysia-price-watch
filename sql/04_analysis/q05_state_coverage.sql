/* =====================================================================
   q05 · How many items and premises does each state have? Is coverage balanced?
   ---------------------------------------------------------------------
   Stakeholder : C. Procurement / supply chain analyst
   Question    : Before comparing states, is each state measured on a
                 similar footing (number of shops, range of items)?
   Method      : Full year. Count distinct premises and items per state,
                 each state's share of all price rows, and the average
                 number of items each of its premises prices.
   Answer      : Coverage is unbalanced: Sarawak has 243 reporting
                 premises, Labuan 16 (15.2x). Johor and KL supply 11.7%
                 and 11.3% of all rows; Labuan 0.6%. Every state prices
                 265-311 items.
   ===================================================================== */

SELECT
    p.state,
    COUNT(DISTINCT f.premise_code)                                      AS premises,
    COUNT(DISTINCT f.item_code)                                         AS items,
    COUNT(*)                                                            AS price_rows,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                  AS pct_of_all_rows,
    ROUND(COUNT(*)::numeric / COUNT(DISTINCT f.premise_code), 0)        AS rows_per_premise,
    COUNT(DISTINCT f.premise_code) FILTER (WHERE p.premise_type_en = 'Wet market')  AS wet_markets,
    COUNT(DISTINCT f.premise_code) FILTER (WHERE p.premise_type_en IN ('Hypermarket','Supermarket')) AS hyper_and_supermarkets
FROM core.fact_price  AS f
JOIN core.dim_premise AS p ON p.premise_code = f.premise_code
GROUP BY p.state
ORDER BY premises DESC;

-- Biggest vs smallest state on each measure
WITH s AS (
    SELECT p.state,
           COUNT(DISTINCT f.premise_code) AS premises,
           COUNT(DISTINCT f.item_code)    AS items
    FROM core.fact_price  AS f
    JOIN core.dim_premise AS p ON p.premise_code = f.premise_code
    GROUP BY p.state
)
SELECT MAX(premises) AS most_premises, MIN(premises) AS fewest_premises,
       ROUND(MAX(premises)::numeric / MIN(premises), 1) AS premises_ratio,
       MAX(items) AS most_items, MIN(items) AS fewest_items
FROM s;
