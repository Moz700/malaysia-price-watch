/* =====================================================================
   q30 · The three most important findings, as one small report table
   ---------------------------------------------------------------------
   Stakeholder : All
   Question    : What are the three numbers a busy manager should take away?
   Method      : Chained CTEs: each finding is computed from the tables (no
                 typed-in numbers), then the three results are stacked with
                 UNION ALL into a 3-row report.
                 F1 (B, retailer): price gap between the cheapest and the
                    dearest shop type on the SAME items (q03 method)
                 F2 (A, KPDN): gap between the dearest and cheapest state
                    for the same basket (q09 method)
                 F3 (C, procurement): how concentrated the year's price
                    increases were (q14 method)
   Answer      : 1) Hypermarkets 9.0% cheaper than sundry shops on the
                 same 181 items. 2) Same basket RM 4,349.65 in KL vs RM
                 3,959.53 in Kedah (+9.9%). 3) 84% of 288 items moved
                 under 5%; three categories made 58% of increases with
                 17% of items.
   ===================================================================== */

WITH
-- ---------- shared: one price per shop per item, September 2026 ----------
sep AS (
    SELECT m.item_code, m.price, p.state, p.premise_type_en
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
),
-- ---------- F1: shop type, same items ----------
f1_items AS (
    SELECT item_code FROM sep GROUP BY item_code HAVING COUNT(DISTINCT premise_type_en) = 5
),
f1_nat AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat
    FROM sep WHERE item_code IN (SELECT item_code FROM f1_items) GROUP BY item_code
),
f1_type AS (
    SELECT s.premise_type_en,
           AVG(t.type_median / n.nat) * 100 AS idx
    FROM (SELECT item_code, premise_type_en,
                 PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS type_median
          FROM sep WHERE item_code IN (SELECT item_code FROM f1_items)
          GROUP BY item_code, premise_type_en) AS t
    JOIN f1_nat AS n ON n.item_code = t.item_code
    JOIN (SELECT DISTINCT premise_type_en FROM sep) AS s ON s.premise_type_en = t.premise_type_en
    GROUP BY s.premise_type_en
),
f1 AS (
    SELECT
        (SELECT premise_type_en FROM f1_type ORDER BY idx ASC  LIMIT 1) AS cheapest_type,
        (SELECT premise_type_en FROM f1_type ORDER BY idx DESC LIMIT 1) AS dearest_type,
        (SELECT MIN(idx) FROM f1_type)                                  AS lo,
        (SELECT MAX(idx) FROM f1_type)                                  AS hi,
        (SELECT COUNT(*) FROM f1_items)                                 AS n_items
),
-- ---------- F2: state basket ----------
f2_basket AS (
    SELECT item_code FROM sep GROUP BY item_code
    HAVING COUNT(DISTINCT state) >= 0.8 * (SELECT COUNT(DISTINCT state) FROM sep)
),
f2_nat AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat
    FROM sep WHERE item_code IN (SELECT item_code FROM f2_basket) GROUP BY item_code
),
f2_state_item AS (
    SELECT state, item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS st
    FROM sep WHERE item_code IN (SELECT item_code FROM f2_basket) GROUP BY state, item_code
),
f2_cost AS (
    SELECT s.state, SUM(COALESCE(si.st, n.nat)) AS cost
    FROM (SELECT DISTINCT state FROM sep) AS s
    CROSS JOIN f2_nat AS n
    LEFT JOIN f2_state_item AS si ON si.state = s.state AND si.item_code = n.item_code
    GROUP BY s.state
),
f2 AS (
    SELECT
        (SELECT state FROM f2_cost ORDER BY cost DESC LIMIT 1) AS dearest_state,
        (SELECT state FROM f2_cost ORDER BY cost ASC  LIMIT 1) AS cheapest_state,
        (SELECT MAX(cost) FROM f2_cost)                        AS hi,
        (SELECT MIN(cost) FROM f2_cost)                        AS lo,
        (SELECT COUNT(*) FROM f2_basket)                       AS n_items
),
-- ---------- F3: concentration of the year's increases ----------
f3_change AS (
    SELECT o.item_code,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.price / o.price - 1) AS chg
    FROM core.fact_premise_item_month AS o
    JOIN core.fact_premise_item_month AS s
      ON s.premise_code = o.premise_code AND s.item_code = o.item_code
     AND s.month = DATE '2026-09-01'
    WHERE o.month = DATE '2025-10-01'
    GROUP BY o.item_code
    HAVING COUNT(*) >= 30
),
f3_cat AS (
    SELECT i.item_category, COUNT(*) AS items, SUM(GREATEST(c.chg, 0)) AS ups
    FROM f3_change AS c JOIN core.dim_item AS i ON i.item_code = c.item_code
    GROUP BY i.item_category
),
f3 AS (
    SELECT
        (SELECT STRING_AGG(item_category, ', ' ORDER BY ups DESC)
           FROM (SELECT item_category, ups FROM f3_cat ORDER BY ups DESC LIMIT 3) AS t) AS top3,
        (SELECT SUM(ups) FROM (SELECT ups FROM f3_cat ORDER BY ups DESC LIMIT 3) AS t)
          / (SELECT SUM(ups) FROM f3_cat)                                               AS top3_share,
        (SELECT SUM(items) FROM (SELECT items, ups FROM f3_cat ORDER BY ups DESC LIMIT 3) AS t)::numeric
          / (SELECT SUM(items) FROM f3_cat)                                             AS top3_item_share,
        (SELECT COUNT(*) FROM f3_change WHERE ABS(chg) <= 0.05)::numeric
          / (SELECT COUNT(*) FROM f3_change)                                            AS share_within_5pct,
        (SELECT COUNT(*) FROM f3_change)                                                AS n_items
)
-- ---------- the report ----------
SELECT 1 AS finding, 'B. Retail category manager' AS stakeholder,
       f1.cheapest_type || 's were ' || ROUND((1 - f1.lo / f1.hi)::numeric * 100, 1)
       || '% cheaper than ' || LOWER(f1.dearest_type) || 's on the same '
       || f1.n_items || ' items (Sep 2026)'                                   AS headline
FROM f1
UNION ALL
SELECT 2, 'A. Consumer and policy analyst (KPDN)',
       'The same ' || f2.n_items || '-item basket cost RM ' || TO_CHAR(ROUND(f2.hi::numeric, 2), 'FM9,990.00')
       || ' in ' || f2.dearest_state || ' vs RM ' || TO_CHAR(ROUND(f2.lo::numeric, 2), 'FM9,990.00')
       || ' in ' || f2.cheapest_state || ': ' || ROUND((f2.hi / f2.lo - 1)::numeric * 100, 1) || '% more'
FROM f2
UNION ALL
SELECT 3, 'C. Procurement / supply chain analyst',
       ROUND(f3.share_within_5pct * 100, 0) || '% of ' || f3.n_items
       || ' items moved less than 5% in a year; 3 categories (' || f3.top3 || ') made '
       || ROUND((f3.top3_share * 100)::numeric, 0) || '% of all increases with '
       || ROUND(f3.top3_item_share * 100, 0) || '% of the items'
FROM f3
ORDER BY finding;
