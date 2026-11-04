/* =====================================================================
   q12 · Premise price index by premise type and state
   ---------------------------------------------------------------------
   Stakeholder : B. Retail category manager
   Question    : Is a shop type cheap everywhere, or only in some states?
                 Is the cheapest format the same for fresh food as for
                 packaged goods?
   Method      : September 2026, one price per shop, shops with 30+ items.
                 Item ratio = shop price / national median. Averaged:
                 12a by type, 12b by type x state, 12c by type x item group,
                 12d fresh produce by type x state.
   Answer      : By format: hypermarket 98.4, supermarket 101.4, mini
                 market 103.4, sundry shop 106.8, wet market 108.2. On
                 fresh produce wet markets score 106.5 vs 97.7 for
                 hypermarkets, and a hypermarket or supermarket beats the
                 wet market in 14 of 16 states; the exceptions are Sabah
                 (wet market 103.5 vs hypermarket 104.7) and Kuala Lumpur
                 (100.5 vs 100.8, a tie).
   ===================================================================== */

DROP TABLE IF EXISTS premise_item_ratio;
CREATE TEMP TABLE premise_item_ratio AS          -- reused by the four queries below
WITH sep AS (
    SELECT premise_code, item_code, price
    FROM core.fact_premise_item_month
    WHERE month = DATE '2026-09-01'
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep GROUP BY item_code
)
SELECT s.premise_code, s.item_code, s.price / n.nat_median AS ratio
FROM sep      AS s
JOIN national AS n ON n.item_code = s.item_code
WHERE s.premise_code IN (SELECT premise_code FROM sep GROUP BY premise_code HAVING COUNT(*) >= 30);

-- 12a. By premise type (each shop counts once)
WITH premise_index AS (
    SELECT premise_code, AVG(ratio) * 100 AS price_index
    FROM premise_item_ratio GROUP BY premise_code
)
SELECT p.premise_type_en,
       COUNT(*)                               AS premises,
       ROUND(AVG(x.price_index)::numeric, 1)  AS avg_price_index
FROM premise_index    AS x
JOIN core.dim_premise AS p ON p.premise_code = x.premise_code
GROUP BY p.premise_type_en
ORDER BY avg_price_index;

-- 12b. Premise type x state, pivoted so each type is a column
WITH premise_index AS (
    SELECT premise_code, AVG(ratio) * 100 AS price_index
    FROM premise_item_ratio GROUP BY premise_code
)
SELECT
    p.state,
    ROUND(AVG(x.price_index) FILTER (WHERE p.premise_type_en = 'Hypermarket')::numeric, 1) AS hypermarket,
    ROUND(AVG(x.price_index) FILTER (WHERE p.premise_type_en = 'Supermarket')::numeric, 1) AS supermarket,
    ROUND(AVG(x.price_index) FILTER (WHERE p.premise_type_en = 'Mini market')::numeric, 1) AS mini_market,
    ROUND(AVG(x.price_index) FILTER (WHERE p.premise_type_en = 'Sundry shop')::numeric, 1) AS sundry_shop,
    ROUND(AVG(x.price_index) FILTER (WHERE p.premise_type_en = 'Wet market')::numeric, 1)  AS wet_market,
    ROUND(AVG(x.price_index)::numeric, 1)                                                  AS all_types
FROM premise_index    AS x
JOIN core.dim_premise AS p ON p.premise_code = x.premise_code
GROUP BY p.state
ORDER BY all_types DESC;

-- 12c. Premise type x item group: does the cheapest format depend on what you buy?
SELECT
    i.item_group_en,
    COUNT(DISTINCT r.item_code) AS items,
    ROUND((AVG(r.ratio) FILTER (WHERE p.premise_type_en = 'Hypermarket') * 100)::numeric, 1) AS hypermarket,
    ROUND((AVG(r.ratio) FILTER (WHERE p.premise_type_en = 'Supermarket') * 100)::numeric, 1) AS supermarket,
    ROUND((AVG(r.ratio) FILTER (WHERE p.premise_type_en = 'Mini market') * 100)::numeric, 1) AS mini_market,
    ROUND((AVG(r.ratio) FILTER (WHERE p.premise_type_en = 'Sundry shop') * 100)::numeric, 1) AS sundry_shop,
    ROUND((AVG(r.ratio) FILTER (WHERE p.premise_type_en = 'Wet market')  * 100)::numeric, 1) AS wet_market
FROM premise_item_ratio AS r
JOIN core.dim_premise   AS p ON p.premise_code = r.premise_code
JOIN core.dim_item      AS i ON i.item_code    = r.item_code
GROUP BY i.item_group_en
ORDER BY items DESC;

-- 12d. Fresh produce only, by state and type: does the wet-market result hold everywhere?
SELECT
    p.state,
    ROUND((AVG(r.ratio) FILTER (WHERE p.premise_type_en = 'Hypermarket') * 100)::numeric, 1) AS hypermarket,
    ROUND((AVG(r.ratio) FILTER (WHERE p.premise_type_en = 'Supermarket') * 100)::numeric, 1) AS supermarket,
    ROUND((AVG(r.ratio) FILTER (WHERE p.premise_type_en = 'Mini market') * 100)::numeric, 1) AS mini_market,
    ROUND((AVG(r.ratio) FILTER (WHERE p.premise_type_en = 'Sundry shop') * 100)::numeric, 1) AS sundry_shop,
    ROUND((AVG(r.ratio) FILTER (WHERE p.premise_type_en = 'Wet market')  * 100)::numeric, 1) AS wet_market
FROM premise_item_ratio AS r
JOIN core.dim_premise   AS p ON p.premise_code = r.premise_code
JOIN core.dim_item      AS i ON i.item_code    = r.item_code
WHERE i.item_group_en = 'Fresh produce'
GROUP BY p.state
ORDER BY p.state;
