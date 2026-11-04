/* =====================================================================
   q09 · What does an "essentials basket" cost in each state?
   ---------------------------------------------------------------------
   Stakeholder : A. Consumer and policy analyst (KPDN)
   Question    : If a shopper bought one of each widely sold item, how much
                 would the basket cost in each state?
   Method      : September 2026, one price per shop.
                 1) Basket = items priced in at least 80% of states (13 of 16)
                 2) Basket cost per state = sum of the state's median price
                    for each basket item
                 3) A state that does not price a basket item gets the
                    national median for it, so every state's basket holds the
                    same items. The output shows how many items were filled
                    in this way.
   Answer      : 265-item basket: RM 4,349.65 in Kuala Lumpur (dearest)
                 vs RM 3,959.53 in Kedah (cheapest), 9.9% more. Labuan
                 had to borrow the national median for 58 items, so read
                 it with care.
   ===================================================================== */

WITH sep AS (
    SELECT m.item_code, m.price, p.state
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
),
basket AS (                                                  -- step 1
    SELECT item_code
    FROM sep
    GROUP BY item_code
    HAVING COUNT(DISTINCT state) >= 0.8 * (SELECT COUNT(DISTINCT state) FROM sep)
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep
    WHERE item_code IN (SELECT item_code FROM basket)
    GROUP BY item_code
),
state_item AS (
    SELECT state, item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS state_median
    FROM sep
    WHERE item_code IN (SELECT item_code FROM basket)
    GROUP BY state, item_code
),
grid AS (                                                    -- every state x every basket item
    SELECT s.state, n.item_code, n.nat_median, si.state_median
    FROM (SELECT DISTINCT state FROM sep) AS s
    CROSS JOIN national AS n
    LEFT JOIN state_item AS si                               -- LEFT JOIN keeps a missing item as NULL
           ON si.state = s.state AND si.item_code = n.item_code
)
SELECT
    state,
    COUNT(*)                                                       AS basket_items,
    COUNT(*) - COUNT(state_median)                                 AS items_filled_with_national,
    ROUND(SUM(COALESCE(state_median, nat_median))::numeric, 2)     AS basket_cost_rm,   -- step 3
    ROUND((SUM(COALESCE(state_median, nat_median)) / SUM(nat_median) * 100)::numeric, 1) AS basket_index,
    RANK() OVER (ORDER BY SUM(COALESCE(state_median, nat_median)) DESC) AS rank_most_expensive
FROM grid
GROUP BY state
ORDER BY basket_cost_rm DESC;

-- What is in the basket, by item group
WITH sep AS (
    SELECT m.item_code, p.state
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
),
basket AS (
    SELECT item_code FROM sep GROUP BY item_code
    HAVING COUNT(DISTINCT state) >= 0.8 * (SELECT COUNT(DISTINCT state) FROM sep)
)
SELECT i.item_group_en, COUNT(*) AS basket_items
FROM basket AS b
JOIN core.dim_item AS i ON i.item_code = b.item_code
GROUP BY ROLLUP (i.item_group_en)
ORDER BY basket_items DESC;
