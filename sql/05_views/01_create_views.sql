/* =====================================================================
   Reporting layer: views in the "mart" schema
   ---------------------------------------------------------------------
   The dashboards read only these objects, so the star-schema joins and
   business rules live in one place. The heaviest query (weekly spikes)
   is a materialized view; see 02_materialized_view_timing.sql.

   Latest month used for the snapshot views: September 2026.
   ===================================================================== */

-- ---------------------------------------------------------------------
-- 1. mart.v_state_basket  (dashboard page 1: affordability map)
--    Basket cost and index per state, September 2026 (logic of q09)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW mart.v_state_basket AS
WITH sep AS (
    SELECT m.item_code, m.price, p.state
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
),
basket AS (
    SELECT item_code FROM sep GROUP BY item_code
    HAVING COUNT(DISTINCT state) >= 0.8 * (SELECT COUNT(DISTINCT state) FROM sep)
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep WHERE item_code IN (SELECT item_code FROM basket) GROUP BY item_code
),
state_item AS (
    SELECT state, item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS state_median
    FROM sep WHERE item_code IN (SELECT item_code FROM basket) GROUP BY state, item_code
),
grid AS (
    SELECT s.state, n.item_code, n.nat_median, si.state_median
    FROM (SELECT DISTINCT state FROM sep) AS s
    CROSS JOIN national AS n
    LEFT JOIN state_item AS si ON si.state = s.state AND si.item_code = n.item_code
)
SELECT
    state,
    COUNT(*)                                                                         AS basket_items,
    COUNT(*) - COUNT(state_median)                                                   AS items_filled_with_national,
    ROUND(SUM(COALESCE(state_median, nat_median))::numeric, 2)                       AS basket_cost_rm,
    ROUND((SUM(COALESCE(state_median, nat_median)) / SUM(nat_median) * 100)::numeric, 1) AS basket_index
FROM grid
GROUP BY state;

-- ---------------------------------------------------------------------
-- 2. mart.v_district_basket  (page 1: district drill-down, logic of q10)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW mart.v_district_basket AS
WITH sep AS (
    SELECT m.item_code, m.price, p.state, p.district
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.month = DATE '2026-09-01'
),
basket AS (
    SELECT item_code FROM sep GROUP BY item_code
    HAVING COUNT(DISTINCT state) >= 0.8 * (SELECT COUNT(DISTINCT state) FROM sep)
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep WHERE item_code IN (SELECT item_code FROM basket) GROUP BY item_code
),
district_item AS (
    SELECT state, district, item_code, COUNT(*) AS shops,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS d_median
    FROM sep WHERE item_code IN (SELECT item_code FROM basket)
    GROUP BY state, district, item_code
)
SELECT
    d.state,
    d.district,
    MAX(d.shops)                                         AS max_shops_per_item,
    COUNT(*)                                             AS basket_items_priced,
    ROUND((AVG(d.d_median / n.nat_median) * 100)::numeric, 1) AS basket_index,
    COUNT(*) >= 0.5 * (SELECT COUNT(*) FROM basket)      AS enough_items_to_score
FROM district_item AS d
JOIN national      AS n ON n.item_code = d.item_code
GROUP BY d.state, d.district;

-- ---------------------------------------------------------------------
-- 3. mart.v_premise_index  (page 2: price positioning, logic of q11/q19)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW mart.v_premise_index AS
WITH sep AS (
    SELECT premise_code, item_code, price
    FROM core.fact_premise_item_month
    WHERE month = DATE '2026-09-01'
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep GROUP BY item_code
),
idx AS (
    SELECT s.premise_code, COUNT(*) AS items_priced, AVG(s.price / n.nat_median) * 100 AS price_index
    FROM sep AS s JOIN national AS n ON n.item_code = s.item_code
    GROUP BY s.premise_code
    HAVING COUNT(*) >= 30
)
SELECT
    p.premise_code,
    p.premise,
    p.premise_type_en                                                   AS premise_type,
    p.state,
    p.district,
    x.items_priced,
    ROUND(x.price_index::numeric, 1)                                    AS price_index,
    NTILE(4) OVER (PARTITION BY p.state ORDER BY x.price_index)         AS price_quartile_in_state
FROM idx AS x
JOIN core.dim_premise AS p ON p.premise_code = x.premise_code;

-- ---------------------------------------------------------------------
-- 4. mart.v_premise_item_price  (page 2: item slicer)
--    Every shop's September price for every item, against the national median
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW mart.v_premise_item_price AS
WITH sep AS (
    SELECT premise_code, item_code, price, n_reports
    FROM core.fact_premise_item_month
    WHERE month = DATE '2026-09-01'
),
national AS (
    SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS nat_median
    FROM sep GROUP BY item_code
)
SELECT
    s.premise_code,
    p.premise,
    p.premise_type_en                                   AS premise_type,
    p.state,
    p.district,
    s.item_code,
    i.item,
    i.unit,
    i.item_group_en                                     AS item_group,
    i.item_category,
    s.price                                             AS price_rm,
    ROUND(n.nat_median::numeric, 2)                     AS national_median_rm,
    ROUND((s.price / n.nat_median * 100)::numeric, 1)   AS price_vs_national,   -- 100 = national median
    s.n_reports
FROM sep AS s
JOIN national         AS n ON n.item_code    = s.item_code
JOIN core.dim_premise AS p ON p.premise_code = s.premise_code
JOIN core.dim_item    AS i ON i.item_code    = s.item_code;

-- ---------------------------------------------------------------------
-- 5. mart.v_item_monthly  (page 3: trends, logic of q17/q20)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW mart.v_item_monthly AS
WITH item_month AS (
    SELECT item_code, month, COUNT(*) AS premises,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median_price
    FROM core.fact_premise_item_month
    GROUP BY item_code, month
)
SELECT
    m.item_code,
    i.item,
    i.unit,
    i.item_group_en                                                                     AS item_group,
    i.item_category,
    m.month,
    m.premises,
    ROUND(m.median_price::numeric, 2)                                                   AS median_price_rm,
    ROUND(((m.median_price / LAG(m.median_price) OVER w - 1) * 100)::numeric, 2)        AS mom_change_pct,
    ROUND(((m.median_price / FIRST_VALUE(m.median_price) OVER w - 1) * 100)::numeric, 2) AS change_since_first_month_pct
FROM item_month    AS m
JOIN core.dim_item AS i ON i.item_code = m.item_code
WINDOW w AS (PARTITION BY m.item_code ORDER BY m.month);

-- ---------------------------------------------------------------------
-- 6. mart.v_festive_effect  (page 3: festive comparison, logic of q21/q22)
--    One row per festival x state x item set (staples / control)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW mart.v_festive_effect AS
WITH staple_items AS (
    SELECT item_code FROM core.dim_item
    WHERE item_category IN ('AYAM', 'DAGING', 'TELUR', 'KELAPA', 'BAWANG', 'SANTAN (KOTAK)')
       OR item_code IN (92, 93, 94, 716, 1925, 1926, 1927)
),
windows AS (
    SELECT festival, festival_date,
           festival_date - 14 AS pre_start,  festival_date - 1  AS pre_end,
           festival_date - 42 AS base_start, festival_date - 15 AS base_end
    FROM core.dim_festival
),
pairs AS (
    SELECT w.festival, w.festival_date, f.premise_code, f.item_code,
           AVG(f.price) FILTER (WHERE f.date BETWEEN w.pre_start  AND w.pre_end)  AS pre_avg,
           AVG(f.price) FILTER (WHERE f.date BETWEEN w.base_start AND w.base_end) AS base_avg
    FROM windows AS w
    JOIN core.fact_price AS f ON f.date BETWEEN w.base_start AND w.pre_end
    GROUP BY w.festival, w.festival_date, f.premise_code, f.item_code
)
SELECT
    pr.festival,
    pr.festival_date,
    p.state,
    CASE WHEN pr.item_code IN (SELECT item_code FROM staple_items)
         THEN 'Festive staples' ELSE 'Other items (control)' END          AS item_set,
    COUNT(*)                                                                AS matched_pairs,
    ROUND((AVG(pr.pre_avg / pr.base_avg - 1) * 100)::numeric, 2)            AS mean_change_pct,
    ROUND(100.0 * AVG(CASE WHEN pr.pre_avg > pr.base_avg THEN 1 ELSE 0 END), 1) AS pct_pairs_up
FROM pairs AS pr
JOIN core.dim_premise AS p ON p.premise_code = pr.premise_code
WHERE pr.pre_avg IS NOT NULL AND pr.base_avg IS NOT NULL
GROUP BY pr.festival, pr.festival_date, p.state, 4;

-- ---------------------------------------------------------------------
-- 7. mart.mv_item_weekly_spikes  (page 3: spikes, logic of q23)
--    Materialized (stored), because computing it takes ~30 seconds
-- ---------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mart.mv_item_weekly_spikes;
CREATE MATERIALIZED VIEW mart.mv_item_weekly_spikes AS
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
),
rolling AS (
    SELECT item_code, week_start, premises, median_price,
           AVG(median_price)    OVER w AS roll_mean,
           STDDEV(median_price) OVER w AS roll_sd,
           COUNT(*)             OVER w AS weeks_in_window
    FROM kept
    WINDOW w AS (PARTITION BY item_code ORDER BY week_start ROWS BETWEEN 8 PRECEDING AND 1 PRECEDING)
),
week_label AS (
    SELECT DATE_TRUNC('week', date)::date AS week_start, MAX(festive_period) AS festive_period
    FROM core.dim_date GROUP BY 1
)
SELECT
    r.item_code,
    i.item,
    i.item_group_en                                        AS item_group,
    r.week_start,
    r.premises,
    ROUND(r.median_price::numeric, 2)                      AS median_price_rm,
    ROUND(r.roll_mean::numeric, 2)                         AS rolling_8wk_mean_rm,
    ROUND(r.roll_sd::numeric, 3)                           AS rolling_8wk_sd,
    (r.weeks_in_window = 8 AND r.roll_sd > 0
     AND r.median_price > r.roll_mean + 2 * r.roll_sd
     AND r.median_price > r.roll_mean * 1.02)              AS is_spike,
    wl.festive_period
FROM rolling AS r
JOIN core.dim_item  AS i  ON i.item_code   = r.item_code
LEFT JOIN week_label AS wl ON wl.week_start = r.week_start;

CREATE INDEX ON mart.mv_item_weekly_spikes (item_code, week_start);

-- Check: row counts of every mart object
SELECT 'v_state_basket' AS object, COUNT(*) AS rows FROM mart.v_state_basket
UNION ALL SELECT 'v_district_basket',     COUNT(*) FROM mart.v_district_basket
UNION ALL SELECT 'v_premise_index',       COUNT(*) FROM mart.v_premise_index
UNION ALL SELECT 'v_premise_item_price',  COUNT(*) FROM mart.v_premise_item_price
UNION ALL SELECT 'v_item_monthly',        COUNT(*) FROM mart.v_item_monthly
UNION ALL SELECT 'v_festive_effect',      COUNT(*) FROM mart.v_festive_effect
UNION ALL SELECT 'mv_item_weekly_spikes', COUNT(*) FROM mart.mv_item_weekly_spikes;
