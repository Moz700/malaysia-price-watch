/* =====================================================================
   q16 · For each item and district, which premise is cheapest most often?
   ---------------------------------------------------------------------
   Stakeholder : B. Retail category manager
   Question    : Day after day, who keeps winning on price? A shop that is
                 cheapest on 25 of 28 days is a price leader; one that
                 is cheapest once is noise.
   Method      : September 2026, daily. On each day, DENSE_RANK the shops
                 pricing an item in a district (3+ shops that day). Count
                 the days each shop is rank 1. The shop with the most wins
                 in each (district, item) is the "price leader".
   Answer      : Leaders win 88.3% of the days they compete. Supermarkets
                 hold 59.3% of price-leader titles with 31.7% of shops;
                 hypermarkets 20.1% with 7.0%; wet markets 4.2% with
                 14.3%.
   ===================================================================== */

DROP TABLE IF EXISTS price_leader;
CREATE TEMP TABLE price_leader AS
WITH daily AS (
    SELECT f.date, f.item_code, f.premise_code, p.state, p.district, f.price,
           DENSE_RANK() OVER (PARTITION BY f.date, p.state, p.district, f.item_code
                              ORDER BY f.price)                                  AS day_rank,
           COUNT(*)     OVER (PARTITION BY f.date, p.state, p.district, f.item_code) AS shops_that_day
    FROM core.fact_price  AS f
    JOIN core.dim_premise AS p ON p.premise_code = f.premise_code
    WHERE f.date >= DATE '2026-09-01' AND f.date < DATE '2026-10-01'
),
wins AS (
    SELECT state, district, item_code, premise_code,
           COUNT(*) FILTER (WHERE day_rank = 1) AS days_cheapest,
           COUNT(*)                             AS days_competed
    FROM daily
    WHERE shops_that_day >= 3
    GROUP BY state, district, item_code, premise_code
),
ranked AS (
    SELECT w.*,
           ROW_NUMBER() OVER (PARTITION BY state, district, item_code
                              ORDER BY days_cheapest DESC, days_competed DESC,
                                       premise_code) AS rn     -- last key breaks ties, so reruns match
    FROM wins AS w
)
SELECT * FROM ranked WHERE rn = 1 AND days_cheapest > 0;

-- 16a. Example: price leaders in Petaling for nine staples
SELECT i.item, p.premise, p.premise_type_en, l.days_cheapest, l.days_competed
FROM price_leader     AS l
JOIN core.dim_premise AS p ON p.premise_code = l.premise_code
JOIN core.dim_item    AS i ON i.item_code    = l.item_code
WHERE l.district = 'Petaling' AND l.item_code IN (2066, 1, 1110, 918, 1589, 1593, 129, 1564, 93)
ORDER BY i.item;

-- 16b. Share of price-leader titles by shop type vs share of competing shops
WITH title_share AS (
    SELECT p.premise_type_en, COUNT(*) AS titles
    FROM price_leader AS l JOIN core.dim_premise AS p ON p.premise_code = l.premise_code
    GROUP BY p.premise_type_en
),
presence AS (
    SELECT p.premise_type_en, COUNT(DISTINCT f.premise_code) AS premises
    FROM core.fact_price AS f JOIN core.dim_premise AS p ON p.premise_code = f.premise_code
    WHERE f.date >= DATE '2026-09-01' AND f.date < DATE '2026-10-01'
    GROUP BY p.premise_type_en
)
SELECT pr.premise_type_en,
       COALESCE(t.titles, 0)                                                     AS leader_titles,
       ROUND(100.0 * COALESCE(t.titles, 0) / SUM(COALESCE(t.titles, 0)) OVER (), 1) AS pct_of_titles,
       ROUND(100.0 * pr.premises / SUM(pr.premises) OVER (), 1)                  AS pct_of_premises
FROM presence AS pr
LEFT JOIN title_share AS t ON t.premise_type_en = pr.premise_type_en
ORDER BY leader_titles DESC;

-- 16c. Share of competed days that leaders win
SELECT
    COUNT(*)                                                                         AS district_item_races,
    ROUND(AVG(100.0 * days_cheapest / days_competed), 1)                             AS avg_leader_win_rate_pct,
    COUNT(*) FILTER (WHERE days_cheapest::numeric / days_competed >= 0.8)            AS leaders_winning_80pct_plus
FROM price_leader;
