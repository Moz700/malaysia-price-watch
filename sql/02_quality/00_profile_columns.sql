/* =====================================================================
   Profile every column before trusting it
   ---------------------------------------------------------------------
   Nulls, ranges and the category labels as written in the source.
   Results feed docs/data_dictionary.md.
   ===================================================================== */

-- P1. Nulls and price range in the raw price table.
--     COUNT(*) - COUNT(col) = number of nulls in that column.
SELECT
    COUNT(*)                         AS total_rows,
    COUNT(*) - COUNT(date)           AS null_date,
    COUNT(*) - COUNT(premise_code)   AS null_premise_code,
    COUNT(*) - COUNT(item_code)      AS null_item_code,
    COUNT(*) - COUNT(price)          AS null_price,
    MIN(price)                       AS min_price,
    MAX(price)                       AS max_price,
    ROUND(AVG(price), 2)             AS avg_price,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median_price
FROM staging.raw_price;

-- P2. How many distinct values each column has
SELECT
    COUNT(DISTINCT date)          AS distinct_dates,
    COUNT(DISTINCT premise_code)  AS distinct_premises,
    COUNT(DISTINCT item_code)     AS distinct_items,
    COUNT(DISTINCT price)         AS distinct_prices
FROM staging.raw_price;

-- P3. Premise types: as written in the lookup, and how many price rows each has.
--     The brackets make hidden spaces visible: '[Pasar Basah ]' has a
--     trailing space, so it is a different label from '[Pasar Basah]'.
--     LEFT JOIN keeps premise types even if they have no price rows.
SELECT
    '[' || p.premise_type || ']'      AS premise_type_as_written,
    COUNT(DISTINCT p.premise_code)    AS premises_in_lookup,
    COUNT(r.premise_code)             AS price_rows
FROM staging.lookup_premise AS p
LEFT JOIN staging.raw_price AS r
       ON r.premise_code = p.premise_code
GROUP BY p.premise_type
ORDER BY price_rows DESC, premises_in_lookup DESC;

-- P4. States: premises in the lookup vs premises that report prices
SELECT
    p.state,
    COUNT(DISTINCT p.premise_code)  AS premises_in_lookup,
    COUNT(DISTINCT r.premise_code)  AS premises_reporting,
    COUNT(r.premise_code)           AS price_rows
FROM staging.lookup_premise AS p
LEFT JOIN staging.raw_price AS r
       ON r.premise_code = p.premise_code
GROUP BY p.state
ORDER BY price_rows DESC;

-- P5. Item groups: items in the lookup vs items that get priced
SELECT
    i.item_group,
    COUNT(DISTINCT i.item_code)  AS items_in_lookup,
    COUNT(DISTINCT r.item_code)  AS items_priced,
    COUNT(r.item_code)           AS price_rows
FROM staging.lookup_item AS i
LEFT JOIN staging.raw_price AS r
       ON r.item_code = i.item_code
GROUP BY i.item_group
ORDER BY price_rows DESC;

-- P6. Item categories with at least one price (inner JOIN drops unpriced ones)
SELECT
    i.item_group,
    i.item_category,
    COUNT(DISTINCT r.item_code)  AS items_priced,
    COUNT(*)                     AS price_rows
FROM staging.raw_price AS r
JOIN staging.lookup_item AS i
  ON i.item_code = r.item_code
GROUP BY i.item_group, i.item_category
ORDER BY i.item_group, price_rows DESC;

-- P7. The 20 most-priced items (most rows)
SELECT
    r.item_code,
    i.item,
    i.unit,
    COUNT(*)                        AS price_rows,
    COUNT(DISTINCT r.premise_code)  AS premises,
    ROUND(AVG(r.price), 2)          AS avg_price
FROM staging.raw_price AS r
JOIN staging.lookup_item AS i
  ON i.item_code = r.item_code
GROUP BY r.item_code, i.item, i.unit
ORDER BY price_rows DESC
LIMIT 20;

-- P8. The 20 most active premises (most rows)
SELECT
    r.premise_code,
    p.premise,
    TRIM(p.premise_type)          AS premise_type,
    p.state,
    COUNT(*)                      AS price_rows,
    COUNT(DISTINCT r.item_code)   AS items,
    COUNT(DISTINCT r.date)        AS days_reported
FROM staging.raw_price AS r
JOIN staging.lookup_premise AS p
  ON p.premise_code = r.premise_code
GROUP BY r.premise_code, p.premise, p.premise_type, p.state
ORDER BY price_rows DESC
LIMIT 20;

-- P9. Calendar days with no price data at all
SELECT
    d::date                        AS missing_date,
    TO_CHAR(d, 'Dy')               AS weekday
FROM generate_series(DATE '2025-10-01', DATE '2026-09-30', INTERVAL '1 day') AS d
WHERE NOT EXISTS (
    SELECT 1 FROM staging.raw_price AS r WHERE r.date = d::date
)
ORDER BY missing_date;

-- P10. Which weekday are prices collected on, by premise type? (September 2026)
--      Each row is shown as a % of its own premise type's total,
--      ordered Monday to Sunday.
SELECT
    TRIM(p.premise_type)                        AS premise_type,
    TO_CHAR(r.date, 'Dy')                       AS weekday,
    COUNT(*)                                    AS price_rows,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY TRIM(p.premise_type)), 1) AS pct_of_type
FROM staging.raw_price      AS r
JOIN staging.lookup_premise AS p ON p.premise_code = r.premise_code
WHERE r.date >= DATE '2026-09-01'
GROUP BY TRIM(p.premise_type), TO_CHAR(r.date, 'Dy'), EXTRACT(ISODOW FROM r.date)
ORDER BY 1, EXTRACT(ISODOW FROM r.date);

-- P11. All rows by weekday, full year
SELECT TO_CHAR(date, 'Dy') AS weekday, COUNT(*) AS price_rows,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_all_rows
FROM staging.raw_price
GROUP BY TO_CHAR(date, 'Dy'), EXTRACT(ISODOW FROM date)
ORDER BY EXTRACT(ISODOW FROM date);
