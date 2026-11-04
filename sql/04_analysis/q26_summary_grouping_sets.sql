/* =====================================================================
   q26 · One summary table: by state, by premise type, and grand total
   ---------------------------------------------------------------------
   Stakeholder : A. Consumer and policy analyst (KPDN)
   Question    : One table for a briefing: coverage and price level by
                 state, by shop type, and for Malaysia as a whole.
   Method      : September 2026 premise price index (q11 method). One
                 GROUPING SETS query stacks three levels: (state),
                 (premise type) and () = grand total. GROUPING() labels
                 the subtotal rows.
   Answer      : 2,141 premises reported in Sep 2026; the 2,087 pricing
                 30+ items average an index of 103.6. Dearest state
                 Putrajaya (111.5), cheapest Perak (98.7); dearest format
                 wet market (108.2), cheapest hypermarket (98.4).
   ===================================================================== */

WITH sep AS (
    SELECT premise_code, item_code, price, n_reports
    FROM core.fact_premise_item_month
    WHERE month = DATE '2026-09-01'
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep GROUP BY item_code
),
premise_index AS (
    SELECT s.premise_code, COUNT(*) AS items, SUM(s.n_reports) AS price_rows,
           AVG(s.price / n.nat_median) * 100 AS price_index
    FROM sep AS s JOIN national AS n ON n.item_code = s.item_code
    GROUP BY s.premise_code
)
SELECT
    CASE WHEN GROUPING(p.state) = 0         THEN 'State'
         WHEN GROUPING(p.premise_type_en) = 0 THEN 'Premise type'
         ELSE 'Malaysia' END                                   AS level,
    COALESCE(p.state, p.premise_type_en, 'All')                AS name,
    COUNT(*)                                                   AS premises,
    SUM(x.price_rows)                                          AS price_rows,
    ROUND(AVG(x.items), 0)                                     AS avg_items_per_premise,
    ROUND(AVG(x.price_index) FILTER (WHERE x.items >= 30)::numeric, 1) AS avg_price_index
FROM premise_index    AS x
JOIN core.dim_premise AS p ON p.premise_code = x.premise_code
GROUP BY GROUPING SETS ((p.state), (p.premise_type_en), ())
ORDER BY GROUPING(p.state), GROUPING(p.premise_type_en), avg_price_index DESC NULLS LAST;
