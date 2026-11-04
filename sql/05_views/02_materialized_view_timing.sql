/* =====================================================================
   Normal view vs materialized view: a timing test
   ---------------------------------------------------------------------
   The same weekly-spike query, read two ways:
     A) as a normal view: PostgreSQL recomputes it from 20.7M rows each time
     B) as the materialized view: PostgreSQL reads the stored result
   REFRESH then measures the cost of bringing B up to date.
   ===================================================================== */

-- A temporary normal view with the same core logic, for the comparison
DROP VIEW IF EXISTS v_item_weekly_spikes_live;
CREATE TEMP VIEW v_item_weekly_spikes_live AS
WITH premise_week AS (
    SELECT item_code, premise_code, DATE_TRUNC('week', date)::date AS week_start, AVG(price) AS p
    FROM core.fact_price
    GROUP BY item_code, premise_code, DATE_TRUNC('week', date)
),
item_week AS (
    SELECT item_code, week_start, COUNT(*) AS premises,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p) AS median_price
    FROM premise_week GROUP BY item_code, week_start
),
usual AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY premises) AS usual_premises
    FROM item_week GROUP BY item_code
),
kept AS (
    SELECT w.* FROM item_week AS w JOIN usual AS u ON u.item_code = w.item_code
    WHERE w.premises >= 0.6 * u.usual_premises AND u.usual_premises >= 50
)
SELECT item_code, week_start, median_price,
       AVG(median_price)    OVER w AS roll_mean,
       STDDEV(median_price) OVER w AS roll_sd
FROM kept
WINDOW w AS (PARTITION BY item_code ORDER BY week_start ROWS BETWEEN 8 PRECEDING AND 1 PRECEDING);

\timing on

-- A) normal view, chicken (item 1): has to rebuild everything first
SELECT COUNT(*), ROUND(AVG(median_price)::numeric, 2) FROM v_item_weekly_spikes_live WHERE item_code = 1;

-- B) materialized view, same question
SELECT COUNT(*), ROUND(AVG(median_price_rm), 2) FROM mart.mv_item_weekly_spikes WHERE item_code = 1;

-- Cost of keeping B fresh (run after new data is loaded)
REFRESH MATERIALIZED VIEW mart.mv_item_weekly_spikes;

\timing off
