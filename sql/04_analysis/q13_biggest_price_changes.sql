/* =====================================================================
   q13 · Which items changed price most between October 2025 and September 2026?
   ---------------------------------------------------------------------
   Stakeholder : C. Procurement / supply chain analyst
   Question    : Over the 12 months, which items rose and fell the most?
   Method      : Two ways, side by side:
                 Naive   = September median / October median - 1.
                           Simple, but if the set of reporting shops changed
                           (quality check 07), this mixes real price change
                           with "different shops".
                 Matched = only (premise, item) pairs that priced the item in
                           both months. Each pair's change = its Sep price /
                           its Oct price - 1; the item's change is the
                           median of its pairs. The headline method: with the
                           same shops and item, it measures price change alone.
                 Items need 30+ matched shops.
   Answer      : Of 288 items, 242 moved less than 5%, 38 rose more than
                 5%, 8 fell more than 5%; median change 0.0%. Tomato
                 +69.4% (95% of 1,518 shops raised it). The naive method
                 was off by more than 2 points for 82 items.
   ===================================================================== */

DROP TABLE IF EXISTS item_change;
CREATE TEMP TABLE item_change AS
WITH oct AS (                                     -- each shop's price per item, Oct 2025
    SELECT premise_code, item_code, price AS p
    FROM core.fact_premise_item_month
    WHERE month = DATE '2025-10-01'
),
sep AS (                                          -- and in Sep 2026
    SELECT premise_code, item_code, price AS p
    FROM core.fact_premise_item_month
    WHERE month = DATE '2026-09-01'
),
matched AS (                                      -- same shop, same item, both months
    SELECT o.item_code, s.p / o.p - 1 AS pair_change
    FROM oct AS o
    JOIN sep AS s ON s.premise_code = o.premise_code AND s.item_code = o.item_code
),
matched_item AS (
    SELECT item_code,
           COUNT(*)                                                  AS matched_premises,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pair_change)  AS matched_change,
           AVG(CASE WHEN pair_change > 0 THEN 1.0 ELSE 0 END)        AS share_of_shops_raising
    FROM matched GROUP BY item_code
    HAVING COUNT(*) >= 30
),
naive_item AS (
    SELECT o.item_code,
           (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p) FROM sep WHERE sep.item_code = o.item_code)
         / PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY o.p) - 1      AS naive_change
    FROM oct AS o GROUP BY o.item_code
)
SELECT m.item_code, m.matched_premises, m.matched_change, m.share_of_shops_raising, n.naive_change
FROM matched_item AS m
JOIN naive_item   AS n ON n.item_code = m.item_code;

-- 13a. Top 15 risers (matched)
SELECT i.item, i.unit, c.matched_premises,
       ROUND(c.matched_change::numeric * 100, 1)          AS matched_change_pct,
       ROUND(c.naive_change::numeric * 100, 1)            AS naive_change_pct,
       ROUND(c.share_of_shops_raising * 100, 0)           AS pct_shops_raising
FROM item_change AS c JOIN core.dim_item AS i ON i.item_code = c.item_code
ORDER BY c.matched_change DESC
LIMIT 15;

-- 13b. Top 15 fallers (matched)
SELECT i.item, i.unit, c.matched_premises,
       ROUND(c.matched_change::numeric * 100, 1)          AS matched_change_pct,
       ROUND(c.naive_change::numeric * 100, 1)            AS naive_change_pct,
       ROUND(c.share_of_shops_raising * 100, 0)           AS pct_shops_raising
FROM item_change AS c JOIN core.dim_item AS i ON i.item_code = c.item_code
ORDER BY c.matched_change ASC
LIMIT 15;

-- 13c. Overall picture, and how often the naive method gets the direction wrong
SELECT
    COUNT(*)                                                         AS items,
    COUNT(*) FILTER (WHERE matched_change >  0.05)                   AS up_more_than_5pct,
    COUNT(*) FILTER (WHERE matched_change BETWEEN -0.05 AND 0.05)    AS within_5pct,
    COUNT(*) FILTER (WHERE matched_change < -0.05)                   AS down_more_than_5pct,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY matched_change))::numeric * 100, 2) AS median_item_change_pct,
    COUNT(*) FILTER (WHERE ABS(naive_change - matched_change) > 0.02)  AS naive_off_by_over_2pts,
    COUNT(*) FILTER (WHERE naive_change * matched_change < 0)          AS naive_opposite_direction,
    ROUND(AVG(ABS(naive_change - matched_change))::numeric * 100, 1) AS avg_gap_naive_vs_matched_pts
FROM item_change;
