/* =====================================================================
   q15 · Rank premises by price for each item within each district
   ---------------------------------------------------------------------
   Stakeholder : B. Retail category manager
   Question    : In a given district, where does each shop stand on price
                 for each item: who is cheapest, who is second?
   Method      : September 2026. Average price per premise per item, then
                 rank shops inside each (district, item) group.
                 Three ranking functions side by side; they differ only when
                 two shops tie:
                   ROW_NUMBER  1,2,3,4   (ties broken arbitrarily)
                   RANK        1,2,2,4   (ties share, then a gap)
                   DENSE_RANK  1,2,2,3   (ties share, no gap)
   Answer      : Petaling, chicken (standard): Tesco Seksyen 13 cheapest
                 at RM 8.59. 37.1% of shop rankings share their price
                 with at least one other shop in the same district. Where
                 3+ shops compete, hypermarkets rank cheapest 23.0% of
                 the time, wet markets 6.7%.
   ===================================================================== */

DROP TABLE IF EXISTS district_rank;
CREATE TEMP TABLE district_rank AS
WITH premise_item AS (
    SELECT f.premise_code, f.item_code, p.state, p.district,
           ROUND(AVG(f.price), 2) AS avg_price
    FROM core.fact_price  AS f
    JOIN core.dim_premise AS p ON p.premise_code = f.premise_code
    WHERE f.date >= DATE '2026-09-01' AND f.date < DATE '2026-10-01'
    GROUP BY f.premise_code, f.item_code, p.state, p.district
)
SELECT
    pi.*,
    ROW_NUMBER() OVER w AS row_num,
    RANK()       OVER w AS price_rank,
    DENSE_RANK() OVER w AS dense_price_rank,
    COUNT(*)     OVER (PARTITION BY pi.state, pi.district, pi.item_code) AS shops_competing
FROM premise_item AS pi
WINDOW w AS (PARTITION BY pi.state, pi.district, pi.item_code ORDER BY pi.avg_price);

-- 15a. Example: chicken (standard) in Petaling, Selangor
SELECT p.premise, p.premise_type_en, r.avg_price, r.row_num, r.price_rank, r.dense_price_rank
FROM district_rank    AS r
JOIN core.dim_premise AS p ON p.premise_code = r.premise_code
WHERE r.district = 'Petaling' AND r.item_code = 1
ORDER BY r.price_rank, p.premise;

-- 15b. How often do shops tie on price?
--      tie_size = how many shops in the same (district, item) charge exactly this price.
--      rows_ranked_after_a_tie counts only the 2nd, 3rd... shop of each tie
--      (where RANK and ROW_NUMBER disagree); rows_sharing_a_price counts all of them.
SELECT
    COUNT(*)                                                         AS shop_item_rankings,
    COUNT(*) FILTER (WHERE price_rank <> row_num)                    AS rows_ranked_after_a_tie,
    COUNT(*) FILTER (WHERE tie_size > 1)                             AS rows_sharing_a_price,
    ROUND(100.0 * COUNT(*) FILTER (WHERE tie_size > 1) / COUNT(*), 1) AS pct_sharing_a_price,
    COUNT(DISTINCT (state, district, item_code))                     AS district_item_groups
FROM (
    SELECT r.*, COUNT(*) OVER (PARTITION BY state, district, item_code, avg_price) AS tie_size
    FROM district_rank AS r
) AS t;

-- 15c. Which shop types hold the #1 (cheapest) spot, where 3+ shops compete?
SELECT
    p.premise_type_en,
    COUNT(*) FILTER (WHERE r.price_rank = 1)                                    AS times_ranked_cheapest,
    COUNT(*)                                                                    AS rankings_entered,
    ROUND(100.0 * COUNT(*) FILTER (WHERE r.price_rank = 1) / COUNT(*), 1)       AS win_rate_pct
FROM district_rank    AS r
JOIN core.dim_premise AS p ON p.premise_code = r.premise_code
WHERE r.shops_competing >= 3
GROUP BY p.premise_type_en
ORDER BY win_rate_pct DESC;
