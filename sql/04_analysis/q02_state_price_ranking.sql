/* =====================================================================
   q02 · Most and least expensive state for the 10 most common items
   ---------------------------------------------------------------------
   Stakeholder : A. Consumer and policy analyst (KPDN)
   Question    : For the 10 items that the most shops price, which state
                 is the most expensive and which the cheapest?
   Method      : September 2026, one price per shop (fact_premise_item_month).
                 1) the 10 items priced by the most premises
                 2) median price of each item in each state
                 3) divide by the item's national median -> 1.00 = national;
                    average the 10 ratios per state, x 100 = state index
                 Ratios, not raw RM, so a RM 14/kg chilli and a RM 4/kg onion
                 count equally.
   Answer      : Sabah is the dearest state on the 10 most widely priced
                 items (index 105.9) and Perlis the cheapest (97.1). Seven
                 of the 10 are packaged goods (curry and chilli powder,
                 sugar, boxed santan, instant noodles, chilli sauce); the
                 other three are onions, garlic and ginger.
   ===================================================================== */

WITH sep AS (
    SELECT m.item_code, m.price, p.state
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
),
top_items AS (                                       -- step 1
    SELECT item_code, COUNT(*) AS premises
    FROM sep
    GROUP BY item_code
    ORDER BY premises DESC
    LIMIT 10
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep
    WHERE item_code IN (SELECT item_code FROM top_items)
    GROUP BY item_code
),
state_item AS (                                      -- step 2
    SELECT state, item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS state_median
    FROM sep
    WHERE item_code IN (SELECT item_code FROM top_items)
    GROUP BY state, item_code
)
SELECT                                               -- step 3
    s.state,
    COUNT(*)                                                         AS items_compared,
    ROUND(AVG(s.state_median / n.nat_median)::numeric * 100, 1)      AS price_index,   -- 100 = national
    RANK() OVER (ORDER BY AVG(s.state_median / n.nat_median) DESC)   AS rank_most_expensive
FROM state_item AS s
JOIN national   AS n ON n.item_code = s.item_code
GROUP BY s.state
ORDER BY price_index DESC;

-- Which 10 items were used (for the write-up)
SELECT i.item_code, i.item, i.unit, COUNT(*) AS premises
FROM core.fact_premise_item_month AS m
JOIN core.dim_item                AS i ON i.item_code = m.item_code
WHERE m.month = DATE '2026-09-01'
GROUP BY i.item_code, i.item, i.unit
ORDER BY premises DESC
LIMIT 10;
