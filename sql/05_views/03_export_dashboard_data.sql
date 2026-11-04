/* =====================================================================
   Export the mart data for the web dashboard (CSV files in dashboard/data)
   ---------------------------------------------------------------------
   Run with psql from the repo root, after sql/run_all.sql:

     psql -U postgres -d pricewatch -f sql/05_views/03_export_dashboard_data.sql

   Optional: -v outdir="some/folder"   (default: dashboard/data)

   Files 1-6 are the mart objects exactly as they are.
   Files 7-8 shrink mart.v_premise_item_price (about 239,000 rows, 35 MB)
   to sizes a web page can load quickly:
     7. one row per item x state x shop type (median, lowest, highest price)
     8. the lowest price per item and state, with one example shop
   Snapshot month for the price views: September 2026.
   ===================================================================== */

\set ON_ERROR_STOP on

\if :{?outdir}
\else
  \set outdir 'dashboard/data'
\endif
\cd :outdir

-- 1. Basket cost and index per state (page 1)
\copy (SELECT * FROM mart.v_state_basket ORDER BY basket_index DESC, state) TO 'state_basket.csv' WITH (FORMAT csv, HEADER true)

-- 2. Basket index per district (page 1, drill-down)
\copy (SELECT * FROM mart.v_district_basket ORDER BY state, basket_index DESC, district) TO 'district_basket.csv' WITH (FORMAT csv, HEADER true)

-- 3. Price index per shop (page 2)
\copy (SELECT * FROM mart.v_premise_index ORDER BY state, price_index, premise_code) TO 'premise_index.csv' WITH (FORMAT csv, HEADER true)

-- 4. Monthly national median per item (page 3)
\copy (SELECT * FROM mart.v_item_monthly ORDER BY item_code, month) TO 'item_monthly.csv' WITH (FORMAT csv, HEADER true)

-- 5. Festive effect per festival, state and item set (page 3)
\copy (SELECT * FROM mart.v_festive_effect ORDER BY festival_date, state, item_set) TO 'festive_effect.csv' WITH (FORMAT csv, HEADER true)

-- 6. Weekly median and spike flag per item (page 3)
\copy (SELECT * FROM mart.mv_item_weekly_spikes ORDER BY item_code, week_start) TO 'weekly_spikes.csv' WITH (FORMAT csv, HEADER true)

-- 7. Item price by state and shop type (page 2, item explorer)
\copy (SELECT item_code, item, unit, item_group, item_category, state, premise_type, COUNT(*) AS shops, ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_rm)::numeric, 2) AS median_price_rm, MIN(price_rm) AS min_price_rm, MAX(price_rm) AS max_price_rm, MAX(national_median_rm) AS national_median_rm FROM mart.v_premise_item_price GROUP BY item_code, item, unit, item_group, item_category, state, premise_type ORDER BY item_code, state, premise_type) TO 'item_price_by_state_type.csv' WITH (FORMAT csv, HEADER true)

-- 8. Lowest price per item and state, with one example shop (ties: lowest premise_code)
\copy (WITH p AS (SELECT *, MIN(price_rm) OVER (PARTITION BY item_code, state) AS low, COUNT(*) OVER (PARTITION BY item_code, state) AS n FROM mart.v_premise_item_price) SELECT DISTINCT ON (item_code, state) item_code, item, unit, state, price_rm AS lowest_price_rm, COUNT(*) FILTER (WHERE price_rm = low) OVER (PARTITION BY item_code, state) AS shops_at_lowest_price, n AS shops_compared, premise AS example_shop, premise_type AS example_shop_type, district AS example_shop_district, national_median_rm FROM p ORDER BY item_code, state, price_rm, premise_code) TO 'cheapest_by_item_state.csv' WITH (FORMAT csv, HEADER true)

-- Row counts of the source objects, for the log
SELECT 'state_basket' AS file, COUNT(*) AS rows FROM mart.v_state_basket
UNION ALL SELECT 'district_basket', COUNT(*) FROM mart.v_district_basket
UNION ALL SELECT 'premise_index',   COUNT(*) FROM mart.v_premise_index
UNION ALL SELECT 'item_monthly',    COUNT(*) FROM mart.v_item_monthly
UNION ALL SELECT 'festive_effect',  COUNT(*) FROM mart.v_festive_effect
UNION ALL SELECT 'weekly_spikes',   COUNT(*) FROM mart.mv_item_weekly_spikes
UNION ALL SELECT 'item_price_by_state_type', COUNT(*) FROM (SELECT 1 FROM mart.v_premise_item_price GROUP BY item_code, state, premise_type) AS g
UNION ALL SELECT 'cheapest_by_item_state',   COUNT(*) FROM (SELECT 1 FROM mart.v_premise_item_price GROUP BY item_code, state) AS g;
