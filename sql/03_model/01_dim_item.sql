/* =====================================================================
   core.dim_item: one row per item
   ---------------------------------------------------------------------
   Describes each item in the price facts: what it is, its unit and
   its category.

   item_code is the primary key: PostgreSQL refuses duplicate or NULL
   codes and builds an index on the column.

   Clean-ups applied:
     - drop the placeholder row item_code = -1 (blank name)
     - TRIM() stray spaces from every text column
     - add item_group_en: an English label for the 8 Malay group names,
       so the dashboard reads well for non-Malay readers
   ===================================================================== */

DROP TABLE IF EXISTS core.dim_item CASCADE;   -- CASCADE also drops FKs that point here

CREATE TABLE core.dim_item (
    item_code      INTEGER PRIMARY KEY,
    item           TEXT    NOT NULL,
    unit           TEXT,
    item_group     TEXT    NOT NULL,
    item_group_en  TEXT    NOT NULL,
    item_category  TEXT    NOT NULL
);

INSERT INTO core.dim_item (item_code, item, unit, item_group, item_group_en, item_category)
SELECT
    item_code,
    TRIM(item),
    TRIM(unit),
    TRIM(item_group),
    CASE TRIM(item_group)
        WHEN 'BARANGAN SEGAR'           THEN 'Fresh produce'
        WHEN 'BARANGAN BERBUNGKUS'      THEN 'Packaged goods'
        WHEN 'BARANGAN KERING'          THEN 'Dry goods'
        WHEN 'SUSU DAN BARANGAN BAYI'   THEN 'Milk and baby products'
        WHEN 'MINUMAN'                  THEN 'Beverages'
        WHEN 'PRODUK KEBERSIHAN'        THEN 'Household and hygiene'
        WHEN 'MAKANAN SIAP MASAK'       THEN 'Cooked food'
        WHEN 'BARANGAN KEDAI SERBANEKA' THEN 'Convenience store goods'
        ELSE 'Other'
    END,
    TRIM(item_category)
FROM staging.lookup_item
WHERE item_code > 0              -- removes the -1 placeholder
  AND item IS NOT NULL;

-- Check: 796 items expected (797 lookup rows minus the placeholder)
SELECT item_group_en, COUNT(*) AS items
FROM core.dim_item
GROUP BY item_group_en
ORDER BY items DESC;
