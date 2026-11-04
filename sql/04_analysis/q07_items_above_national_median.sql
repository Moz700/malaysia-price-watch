/* =====================================================================
   q07 · How many items does each shop type price above the national median?
   ---------------------------------------------------------------------
   Stakeholder : B. Retail category manager
   Question    : For hypermarkets (the chain-style format), how many items
                 are priced above the national median, and how does that
                 compare with the other formats?
   Method      : September 2026, one price per shop. Median per item per
                 premise type vs the item's national median. Count items
                 above / below / equal.
   Answer      : Hypermarkets priced 20.0% of their items above the
                 national median; supermarkets 32.4%, mini markets 43.6%,
                 wet markets 56.9%, sundry shops 67.9%.
   ===================================================================== */

WITH sep AS (                                      -- one price per shop per item
    SELECT m.item_code, m.price, p.premise_type_en
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep GROUP BY item_code
),
type_item AS (
    SELECT premise_type_en, item_code,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS type_median
    FROM sep GROUP BY premise_type_en, item_code
)
SELECT
    t.premise_type_en,
    COUNT(*)                                                         AS items_priced,
    SUM(CASE WHEN t.type_median > n.nat_median THEN 1 ELSE 0 END)    AS items_above_national,
    COUNT(*) FILTER (WHERE t.type_median < n.nat_median)             AS items_below_national,
    COUNT(*) FILTER (WHERE t.type_median = n.nat_median)             AS items_at_national,
    ROUND(100.0 * SUM(CASE WHEN t.type_median > n.nat_median THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_above
FROM type_item AS t
JOIN national  AS n ON n.item_code = t.item_code
GROUP BY t.premise_type_en
ORDER BY pct_above DESC;

-- Hypermarkets only, split by item group: where are they above the market?
WITH sep AS (                                      -- one price per shop per item
    SELECT m.item_code, m.price, p.premise_type_en
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep GROUP BY item_code
),
hyper AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS hyper_median
    FROM sep WHERE premise_type_en = 'Hypermarket' GROUP BY item_code
)
SELECT
    i.item_group_en,
    COUNT(*)                                              AS items,
    COUNT(*) FILTER (WHERE h.hyper_median > n.nat_median) AS above,
    COUNT(*) FILTER (WHERE h.hyper_median < n.nat_median) AS below,
    ROUND(AVG(h.hyper_median / n.nat_median)::numeric * 100, 1) AS hyper_index   -- 100 = national
FROM hyper AS h
JOIN national      AS n ON n.item_code = h.item_code
JOIN core.dim_item AS i ON i.item_code = h.item_code
GROUP BY i.item_group_en
ORDER BY hyper_index DESC;
