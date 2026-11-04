/* =====================================================================
   q28 · Premises that stopped reporting for a month or more
   ---------------------------------------------------------------------
   Stakeholder : B. Retail category manager (and the data owner, KPDN)
   Question    : Which shops have holes in their reporting (whole months
                 with no prices between their first and last report), and
                 which went quiet before the end of the period?
   Method      : 1) every month each premise should appear in: from its
                    first month to its last, built with generate_series()
                 2) anti-join (NOT EXISTS) against the months it did report
                 3) what is left = gap months
   Answer      : Reporting is continuous once a shop starts: only 8
                 premises have internal gaps (16 months in total). Shops
                 that stop tend to leave for good: 6.3% of supermarkets
                 and 6.1% of sundry shops stopped before Sep 2026.
   ===================================================================== */

DROP TABLE IF EXISTS premise_gap_month;
CREATE TEMP TABLE premise_gap_month AS
WITH premise_months AS (                          -- months each premise actually reported
    SELECT DISTINCT premise_code, DATE_TRUNC('month', date)::date AS month
    FROM core.fact_price
),
span AS (
    SELECT premise_code, MIN(month) AS first_month, MAX(month) AS last_month
    FROM premise_months GROUP BY premise_code
),
expected AS (                                     -- step 1
    SELECT s.premise_code, g.month::date AS month
    FROM span AS s
    CROSS JOIN LATERAL generate_series(s.first_month, s.last_month, INTERVAL '1 month') AS g(month)
)
SELECT e.premise_code, e.month
FROM expected AS e
WHERE NOT EXISTS (                                -- step 2
    SELECT 1 FROM premise_months AS pm
    WHERE pm.premise_code = e.premise_code AND pm.month = e.month
);

-- 28a. How many premises have gaps, and how long?
SELECT COUNT(DISTINCT premise_code)       AS premises_with_gaps,
       COUNT(*)                           AS gap_months_total,
       MAX(n)                             AS longest_total_gap_months
FROM (SELECT premise_code, COUNT(*) OVER (PARTITION BY premise_code) AS n, month FROM premise_gap_month) AS g;

-- 28b. Gaps by month: was there a month when many shops went missing?
SELECT month, COUNT(*) AS premises_missing
FROM premise_gap_month
GROUP BY month
ORDER BY month;

-- 28c. Premises that went quiet before September 2026 (last report earlier), by type
SELECT premise_type_en,
       COUNT(*) FILTER (WHERE last_seen < DATE '2026-09-01')                         AS stopped_early,
       COUNT(*) FILTER (WHERE reporting_pattern IS DISTINCT FROM 'No prices in period') AS reported_at_all,
       ROUND(100.0 * COUNT(*) FILTER (WHERE last_seen < DATE '2026-09-01')
             / NULLIF(COUNT(*) FILTER (WHERE reporting_pattern IS DISTINCT FROM 'No prices in period'), 0), 1) AS pct_stopped
FROM core.dim_premise
GROUP BY premise_type_en
HAVING COUNT(*) FILTER (WHERE reporting_pattern IS DISTINCT FROM 'No prices in period') > 0
ORDER BY pct_stopped DESC;
