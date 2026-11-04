/* =====================================================================
   q10 · Which district has the cheapest basket within each state?
   ---------------------------------------------------------------------
   Stakeholder : A. Consumer and policy analyst (KPDN)
   Question    : Inside each state, where is the basket cheapest, where is
                 it dearest, and how big is the gap?
   Method      : September 2026, same basket as q09, one price per shop.
                 Districts do not all price every basket item, so each is
                 scored with an index: the average of (district median /
                 national median) over the basket items it does price
                 (100 = national). A district must price at least half the
                 basket to be scored. The cheapest district per state is the
                 one whose index equals the lowest index in its state
                 (correlated subquery).
   Answer      : Cheapest district nationally: Bagan Datuk, Perak (91.4);
                 dearest scored: Limbang, Sarawak (113.9). Widest gap
                 inside a state: Kuala Lumpur, 100.4 (Bandar Tun Razak)
                 to 112.0 (Segambut).
   ===================================================================== */

DROP TABLE IF EXISTS district_index;
CREATE TEMP TABLE district_index AS
WITH sep AS (
    SELECT m.item_code, m.price, p.state, p.district
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
),
basket AS (
    SELECT item_code FROM sep GROUP BY item_code
    HAVING COUNT(DISTINCT state) >= 0.8 * (SELECT COUNT(DISTINCT state) FROM sep)
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep WHERE item_code IN (SELECT item_code FROM basket)
    GROUP BY item_code
),
district_item AS (
    SELECT state, district, item_code,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS d_median
    FROM sep WHERE item_code IN (SELECT item_code FROM basket)
    GROUP BY state, district, item_code
)
SELECT
    d.state,
    d.district,
    COUNT(*)                                 AS basket_items_priced,
    AVG(d.d_median / n.nat_median) * 100     AS basket_index
FROM district_item AS d
JOIN national      AS n ON n.item_code = d.item_code
GROUP BY d.state, d.district
HAVING COUNT(*) >= 0.5 * (SELECT COUNT(*) FROM basket);

-- 10a. Cheapest district in each state (correlated subquery)
SELECT
    d.state,
    d.district                        AS cheapest_district,
    ROUND(d.basket_index::numeric, 1) AS basket_index,
    d.basket_items_priced
FROM district_index AS d
WHERE d.basket_index = (
        SELECT MIN(d2.basket_index)
        FROM district_index AS d2
        WHERE d2.state = d.state          -- same state as the outer row
      )
ORDER BY basket_index;

-- 10b. Spread inside each state: cheapest vs dearest district
SELECT
    state,
    COUNT(*)                                                   AS districts_scored,
    ROUND(MIN(basket_index)::numeric, 1)                       AS cheapest_index,
    ROUND(MAX(basket_index)::numeric, 1)                       AS dearest_index,
    ROUND((MAX(basket_index) - MIN(basket_index))::numeric, 1) AS gap_points
FROM district_index
GROUP BY state
ORDER BY gap_points DESC;

-- 10c. The 10 cheapest and 10 dearest districts in Malaysia
(SELECT 'Cheapest' AS grp, state, district, ROUND(basket_index::numeric, 1) AS basket_index
 FROM district_index ORDER BY basket_index ASC LIMIT 10)
UNION ALL
(SELECT 'Dearest', state, district, ROUND(basket_index::numeric, 1)
 FROM district_index ORDER BY basket_index DESC LIMIT 10);
