/* =====================================================================
   Quality check 4: prices for items missing from lookup_item
   ---------------------------------------------------------------------
   Rule:   drop price rows whose item_code is not in lookup_item.
   Why:    without the lookup we do not know the item's name, unit or
           category, so it cannot be compared or put in a basket.
   ===================================================================== */

-- 4a. Total rows affected
SELECT COUNT(*) AS rows_affected
FROM staging.raw_price AS r
WHERE NOT EXISTS (
    SELECT 1
    FROM staging.lookup_item AS i
    WHERE i.item_code = r.item_code
);

-- 4b. Which codes, how often, and for how long
SELECT
    r.item_code,
    COUNT(*)                       AS price_rows,
    COUNT(DISTINCT r.premise_code) AS premises,
    MIN(r.date)                    AS first_seen,
    MAX(r.date)                    AS last_seen,
    ROUND(AVG(r.price), 2)         AS avg_price
FROM staging.raw_price AS r
WHERE NOT EXISTS (
    SELECT 1 FROM staging.lookup_item AS i WHERE i.item_code = r.item_code
)
GROUP BY r.item_code
ORDER BY price_rows DESC;

-- Result (build run): 313,598 rows across 17 item codes (2023-2096 range),
-- reported all year by up to 882 premises. They look like real items that
-- the published lookup file has not caught up with. This is the biggest
-- single exclusion. Re-download lookup_item.csv later; if the codes
-- appear, re-run the build and they flow in automatically.
