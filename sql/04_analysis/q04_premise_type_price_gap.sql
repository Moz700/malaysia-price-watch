/* =====================================================================
   q04 · Items with the biggest gap between the cheapest and dearest shop type
   ---------------------------------------------------------------------
   Stakeholder : B. Retail category manager
   Question    : On which items does the choice of shop type matter most
                 to the shopper (so price positioning is a real weapon)?
   Method      : September 2026, one price per shop. Median per item per
                 premise type, counting a type only if 10+ of its shops price
                 the item. Gap = dearest type median - cheapest type median,
                 also as % of the cheapest. Items need 3+ types.
   Answer      : Biggest format gap: imported cabbage (China), RM 1.89/kg
                 at hypermarkets vs RM 4.00 at sundry shops (+111.6%).
                 Hypermarkets were the cheapest format for 159 of 242
                 items; the median gap between cheapest and dearest
                 format is 10.0%.
   ===================================================================== */

WITH item_type AS (
    SELECT
        m.item_code,
        p.premise_type_en,
        COUNT(*)                                               AS premises,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.price)   AS type_median
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
    GROUP BY m.item_code, p.premise_type_en
    HAVING COUNT(*) >= 10
),
gaps AS (
    SELECT
        item_code,
        COUNT(*)                                                    AS types_compared,
        MIN(type_median)                                            AS cheapest_median,
        MAX(type_median)                                            AS dearest_median,
        (ARRAY_AGG(premise_type_en ORDER BY type_median ASC))[1]    AS cheapest_type,
        (ARRAY_AGG(premise_type_en ORDER BY type_median DESC))[1]   AS dearest_type
    FROM item_type
    GROUP BY item_code
    HAVING COUNT(*) >= 3
)
SELECT
    i.item,
    i.unit,
    g.types_compared,
    g.cheapest_type,
    ROUND(g.cheapest_median::numeric, 2)                                  AS cheapest_rm,
    g.dearest_type,
    ROUND(g.dearest_median::numeric, 2)                                   AS dearest_rm,
    ROUND((g.dearest_median - g.cheapest_median)::numeric, 2)             AS gap_rm,
    ROUND(((g.dearest_median / g.cheapest_median - 1) * 100)::numeric, 1) AS gap_pct
FROM gaps AS g
JOIN core.dim_item AS i ON i.item_code = g.item_code
ORDER BY gap_pct DESC
LIMIT 15;

-- Across all items: which type is most often the cheapest / the dearest?
WITH item_type AS (
    SELECT m.item_code, p.premise_type_en,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.price) AS type_median
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
    GROUP BY m.item_code, p.premise_type_en
    HAVING COUNT(*) >= 10
),
ends AS (
    SELECT item_code,
           (ARRAY_AGG(premise_type_en ORDER BY type_median ASC))[1]  AS cheapest_type,
           (ARRAY_AGG(premise_type_en ORDER BY type_median DESC))[1] AS dearest_type
    FROM item_type
    GROUP BY item_code
    HAVING COUNT(*) >= 3
)
SELECT t.premise_type_en,
       COUNT(*) FILTER (WHERE e.cheapest_type = t.premise_type_en) AS times_cheapest,
       COUNT(*) FILTER (WHERE e.dearest_type  = t.premise_type_en) AS times_dearest
FROM (SELECT DISTINCT premise_type_en FROM item_type) AS t
CROSS JOIN ends AS e
GROUP BY t.premise_type_en
ORDER BY times_cheapest DESC;

-- Median gap across all items (how much the shop choice matters in general)
WITH item_type AS (
    SELECT m.item_code, p.premise_type_en,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.price) AS type_median
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
    GROUP BY m.item_code, p.premise_type_en
    HAVING COUNT(*) >= 10
)
SELECT COUNT(*) AS items,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap) * 100)::numeric, 1) AS median_gap_pct
FROM (SELECT item_code, MAX(type_median) / MIN(type_median) - 1 AS gap
      FROM item_type GROUP BY item_code HAVING COUNT(*) >= 3) AS g;
