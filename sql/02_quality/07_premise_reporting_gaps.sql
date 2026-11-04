/* =====================================================================
   Quality check 7: premises that start late or stop early
   ---------------------------------------------------------------------
   Rule:   keep these rows (the prices are real). Flag each premise in
           core.dim_premise with its first and last reporting date, and
           use only premises present at both ends of a period when
           measuring price change (q13, q17, q20).
   Why:    if cheap shops drop out and expensive shops join, the average
           price rises even when no shop changed its price. This is a
           "composition effect", a common trap in price data.
   ===================================================================== */

WITH premise_span AS (
    SELECT
        premise_code,
        MIN(date)            AS first_seen,
        MAX(date)            AS last_seen,
        COUNT(DISTINCT date) AS days_reported
    FROM staging.raw_price
    GROUP BY premise_code
)
SELECT
    CASE
        WHEN first_seen <  DATE '2025-11-01' AND last_seen >= DATE '2026-09-01' THEN '1. Full year'
        WHEN first_seen >= DATE '2025-11-01' AND last_seen >= DATE '2026-09-01' THEN '2. Joined late'
        WHEN first_seen <  DATE '2025-11-01' AND last_seen <  DATE '2026-09-01' THEN '3. Stopped early'
        ELSE                                                                         '4. Joined late and stopped early'
    END                              AS reporting_pattern,
    COUNT(*)                         AS premises,
    ROUND(AVG(days_reported))        AS avg_days_reported
FROM premise_span
GROUP BY 1
ORDER BY 1;

-- Premises that went quiet: last report before September 2026
SELECT
    s.premise_code,
    p.premise,
    TRIM(p.premise_type) AS premise_type,
    p.state,
    MIN(s.date) AS first_seen,
    MAX(s.date) AS last_seen
FROM staging.raw_price AS s
JOIN staging.lookup_premise AS p USING (premise_code)
GROUP BY s.premise_code, p.premise, p.premise_type, p.state
HAVING MAX(s.date) < DATE '2026-09-01'
ORDER BY last_seen
LIMIT 25;
