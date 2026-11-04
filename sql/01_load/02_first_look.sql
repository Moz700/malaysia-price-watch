/* =====================================================================
   First look at the loaded staging data
   ---------------------------------------------------------------------
   Four checks: row counts, monthly coverage, overall date range, and
   distinct premises and items.
   ===================================================================== */

-- 1. Total rows in each staging table
SELECT 'raw_price'      AS table_name, COUNT(*) AS row_count FROM staging.raw_price
UNION ALL
SELECT 'lookup_item',    COUNT(*) FROM staging.lookup_item
UNION ALL
SELECT 'lookup_premise', COUNT(*) FROM staging.lookup_premise
UNION ALL
SELECT 'cpi_state',      COUNT(*) FROM ref.cpi_state;

-- 2. Rows per month, with the first and last date in each month
SELECT
    DATE_TRUNC('month', date)::date AS month,
    COUNT(*)                        AS row_count,
    MIN(date)                       AS first_day,
    MAX(date)                       AS last_day,
    COUNT(DISTINCT date)            AS days_with_data
FROM staging.raw_price
GROUP BY 1
ORDER BY 1;

-- 3. Overall date range and how many distinct premises and items appear
SELECT
    MIN(date)                     AS first_date,
    MAX(date)                     AS last_date,
    COUNT(DISTINCT premise_code)  AS distinct_premises,
    COUNT(DISTINCT item_code)     AS distinct_items
FROM staging.raw_price;

-- 4. Eyeball 20 raw rows
SELECT *
FROM staging.raw_price
LIMIT 20;
