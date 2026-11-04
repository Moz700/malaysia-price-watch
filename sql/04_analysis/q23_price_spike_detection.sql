/* =====================================================================
   q23 · Detect price spikes: weeks far above an item's recent normal
   ---------------------------------------------------------------------
   Stakeholder : C. Procurement / supply chain analyst
   Question    : When did an item's national price jump to more than 2
                 standard deviations above its own recent average? Do the
                 spikes bunch up before festivals?
   Why weekly  : 92-96% of mini-market and sundry-shop prices are
                 collected on Mondays (see docs/data_dictionary.md). A daily
                 median therefore mixes different shops on Mondays than on
                 other days and swings by weekday even when no price moved.
                 A weekly median uses the same mix of shops every week.
   Method      : 1) weekly national median per item: each shop's weekly
                    average, then the median across shops. Weeks where fewer
                    than 60% of the item's usual number of shops reported
                    (public-holiday Mondays) are dropped.
                 2) for each week, mean and standard deviation of the
                    previous 8 kept weeks (excluding this week, so a
                    spike cannot hide itself)
                 3) spike = this week's median > mean + 2 x standard deviation
                    and at least 2% above the mean. Without the 2% floor,
                    items whose price almost never moves (baby formula) get
                    "spikes" from a few sen, because their standard
                    deviation is tiny. Such moves are statistically unusual
                    but too small to matter.
                 Items with 50+ shops a week only.
   Answer      : Spike rate was lower in pre-festival weeks (2.83%) than
                 in other weeks (4.52%). December 2025 had the most spike
                 weeks of any month (78, 74 of them fresh produce).
                 Tomato had the most spike weeks (10 of 45).
   ===================================================================== */

DROP TABLE IF EXISTS item_week_spike;
CREATE TEMP TABLE item_week_spike AS
WITH premise_week AS (
    SELECT item_code, premise_code, DATE_TRUNC('week', date)::date AS week_start, AVG(price) AS p
    FROM core.fact_price
    GROUP BY item_code, premise_code, DATE_TRUNC('week', date)
),
item_week AS (                                                              -- step 1
    SELECT item_code, week_start,
           COUNT(*)                                           AS premises,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p)     AS median_price
    FROM premise_week
    GROUP BY item_code, week_start
),
usual AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY premises) AS usual_premises
    FROM item_week GROUP BY item_code
),
kept AS (
    SELECT w.*
    FROM item_week AS w
    JOIN usual     AS u ON u.item_code = w.item_code
    WHERE w.premises >= 0.6 * u.usual_premises
      AND u.usual_premises >= 50
),
rolling AS (                                                                -- step 2
    SELECT item_code, week_start, premises, median_price,
           AVG(median_price)    OVER w AS roll_mean,
           STDDEV(median_price) OVER w AS roll_sd,
           COUNT(*)             OVER w AS weeks_in_window
    FROM kept
    WINDOW w AS (PARTITION BY item_code ORDER BY week_start ROWS BETWEEN 8 PRECEDING AND 1 PRECEDING)
)
SELECT r.*,
       (r.weeks_in_window = 8 AND r.roll_sd > 0
        AND r.median_price > r.roll_mean + 2 * r.roll_sd                    -- step 3: unusual
        AND r.median_price > r.roll_mean * 1.02) AS is_spike                --  ...and at least 2% up
FROM rolling AS r;

-- 23a. Items with the most spike weeks
SELECT i.item, i.item_group_en,
       COUNT(*) FILTER (WHERE s.is_spike)          AS spike_weeks,
       COUNT(*) FILTER (WHERE s.weeks_in_window = 8) AS weeks_tested
FROM item_week_spike AS s
JOIN core.dim_item   AS i ON i.item_code = s.item_code
GROUP BY i.item, i.item_group_en
HAVING COUNT(*) FILTER (WHERE s.is_spike) > 0
ORDER BY spike_weeks DESC
LIMIT 15;

-- 23b. Do spikes bunch before festivals? Spike rate in weeks that overlap a
--      14-day pre-festival window vs all other weeks
WITH week_label AS (
    SELECT DATE_TRUNC('week', date)::date AS week_start,
           MAX(festive_period)            AS festive_period     -- NULL if no day in the week is festive
    FROM core.dim_date
    GROUP BY DATE_TRUNC('week', date)
)
SELECT
    CASE WHEN wl.festive_period IS NULL THEN 'Other weeks' ELSE 'Pre-festival weeks' END AS week_type,
    COUNT(*)                                                                           AS item_weeks_tested,
    COUNT(*) FILTER (WHERE s.is_spike)                                                 AS spike_weeks,
    ROUND(100.0 * COUNT(*) FILTER (WHERE s.is_spike) / COUNT(*), 2)                    AS spike_rate_pct
FROM item_week_spike AS s
JOIN week_label      AS wl ON wl.week_start = s.week_start
WHERE s.weeks_in_window = 8
GROUP BY 1
ORDER BY spike_rate_pct DESC;

-- 23c. Spike weeks by month, and the item groups involved
SELECT TO_CHAR(s.week_start, 'YYYY-MM')                                  AS month,
       COUNT(*) FILTER (WHERE s.is_spike)                                AS spike_weeks,
       COUNT(*) FILTER (WHERE s.is_spike AND i.item_group_en = 'Fresh produce') AS of_which_fresh,
       ROUND(100.0 * COUNT(*) FILTER (WHERE s.is_spike) / COUNT(*), 2)   AS spike_rate_pct
FROM item_week_spike AS s
JOIN core.dim_item   AS i ON i.item_code = s.item_code
WHERE s.weeks_in_window = 8
GROUP BY 1
ORDER BY 1;
