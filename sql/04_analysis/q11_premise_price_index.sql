/* =====================================================================
   q11 · Premise price index: which shops are cheapest overall?
   ---------------------------------------------------------------------
   Stakeholder : B. Retail category manager
   Question    : Ranking every shop on one number, who is cheapest in
                 Malaysia, and who are we up against?
   Method      : September 2026.
                 1) each shop's price for each item (fact_premise_item_month)
                 2) divide by that item's national median  -> item ratio
                 3) premise index = average ratio x 100    (100 = national)
                 Only shops pricing 30+ items, so one cheap item cannot make
                 a shop look cheap.
   Answer      : Cheapest shop: Pasar Gurun, Kedah (84.0); Econsave
                 branches fill most of the top 15. Chains: Tesco/Lotus's
                 89.3-89.4, Econsave 90.2, Mydin 95.0, 99 Speedmart 95.3.
                 Median shop 102.9 (p10 93.6, p90 114.8).
   ===================================================================== */

DROP TABLE IF EXISTS premise_index;
CREATE TEMP TABLE premise_index AS
WITH sep AS (                                                          -- step 1
    SELECT premise_code, item_code, price
    FROM core.fact_premise_item_month
    WHERE month = DATE '2026-09-01'
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep GROUP BY item_code
)
SELECT s.premise_code,                                                 -- steps 2-3
       COUNT(*)                                AS items_priced,
       AVG(s.price / n.nat_median) * 100       AS price_index
FROM sep      AS s
JOIN national AS n ON n.item_code = s.item_code
GROUP BY s.premise_code
HAVING COUNT(*) >= 30;

-- 11a. The 15 cheapest shops in Malaysia
SELECT p.premise, p.premise_type_en, p.state, p.district,
       x.items_priced,
       ROUND(x.price_index::numeric, 1) AS price_index
FROM premise_index    AS x
JOIN core.dim_premise AS p ON p.premise_code = x.premise_code
ORDER BY x.price_index
LIMIT 15;

-- 11b. Distribution of the index across shops
SELECT
    COUNT(*)                                                                      AS premises_scored,
    ROUND(MIN(price_index)::numeric, 1)                                           AS cheapest,
    ROUND((PERCENTILE_CONT(0.1) WITHIN GROUP (ORDER BY price_index))::numeric, 1) AS p10,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_index))::numeric, 1) AS median,
    ROUND((PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY price_index))::numeric, 1) AS p90,
    ROUND(MAX(price_index)::numeric, 1)                                           AS dearest
FROM premise_index;

-- 11c. Chains: shops whose name starts with the same word, 5+ branches
SELECT SPLIT_PART(p.premise, ' ', 1)               AS name_first_word,
       COUNT(*)                                    AS branches,
       ROUND(AVG(x.price_index)::numeric, 1)       AS avg_index,
       ROUND(MIN(x.price_index)::numeric, 1)       AS cheapest_branch,
       ROUND(MAX(x.price_index)::numeric, 1)       AS dearest_branch
FROM premise_index    AS x
JOIN core.dim_premise AS p ON p.premise_code = x.premise_code
GROUP BY SPLIT_PART(p.premise, ' ', 1)
HAVING COUNT(*) >= 5
ORDER BY avg_index
LIMIT 15;
