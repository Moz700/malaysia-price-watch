/* =====================================================================
   q03 · How prices differ by premise type for the same item
   ---------------------------------------------------------------------
   Stakeholder : B. Retail category manager (supermarket chain)
   Question    : For the same item, how much more or less does each type
                 of shop charge than the national median?
   Method      : September 2026, one price per shop. Keep only items sold
                 in all five shop types (hypermarket, supermarket, mini
                 market, sundry shop, wet market) so every type is compared
                 on the SAME items. Median per item per type, divided by the
                 item's national median, averaged per type (x 100).
   Answer      : On the 181 items sold in all five formats: hypermarket
                 95.0, supermarket 97.7, mini market 102.3, wet market
                 104.2, sundry shop 104.3 (100 = national median).
   ===================================================================== */

WITH sep AS (
    SELECT m.item_code, m.price, p.premise_type_en
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
),
common_items AS (                                               -- sold in all 5 types
    SELECT item_code
    FROM sep
    GROUP BY item_code
    HAVING COUNT(DISTINCT premise_type_en) = 5
),
item_type AS (                                                  -- median per item per type
    SELECT item_code, premise_type_en,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS type_median
    FROM sep
    WHERE item_code IN (SELECT item_code FROM common_items)
    GROUP BY item_code, premise_type_en
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep
    WHERE item_code IN (SELECT item_code FROM common_items)
    GROUP BY item_code
)
SELECT
    t.premise_type_en,
    COUNT(*)                                                       AS items_compared,
    ROUND(AVG(t.type_median / n.nat_median)::numeric * 100, 1)     AS price_index,      -- 100 = national median
    COUNT(*) FILTER (WHERE t.type_median < n.nat_median)           AS items_below_national,
    COUNT(*) FILTER (WHERE t.type_median > n.nat_median)           AS items_above_national
FROM item_type AS t
JOIN national  AS n ON n.item_code = t.item_code
GROUP BY t.premise_type_en
ORDER BY price_index;

-- Item by item for the everyday staples, one column per shop type
WITH sep AS (
    SELECT m.item_code, m.price, p.premise_type_en
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
)
SELECT
    i.item,
    i.unit,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.price) FILTER (WHERE s.premise_type_en = 'Hypermarket'))::numeric, 2) AS hypermarket,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.price) FILTER (WHERE s.premise_type_en = 'Supermarket'))::numeric, 2) AS supermarket,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.price) FILTER (WHERE s.premise_type_en = 'Mini market'))::numeric, 2) AS mini_market,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.price) FILTER (WHERE s.premise_type_en = 'Sundry shop'))::numeric, 2) AS sundry_shop,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.price) FILTER (WHERE s.premise_type_en = 'Wet market'))::numeric, 2)  AS wet_market
FROM sep AS s
JOIN core.dim_item AS i ON i.item_code = s.item_code
WHERE s.item_code IN (2066, 1, 1110, 918, 1589, 1593, 129, 1564, 93)
GROUP BY i.item, i.unit
ORDER BY i.item;
