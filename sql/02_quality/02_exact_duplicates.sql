/* =====================================================================
   Quality check 2: exact duplicate rows
   ---------------------------------------------------------------------
   Rule:   if the same (date, premise, item, price) appears twice, keep one.
   Why:    a duplicate double-counts that shop in every average.
   ===================================================================== */

SELECT
    COUNT(*)                 AS duplicated_groups,
    COALESCE(SUM(n - 1), 0)  AS extra_rows_to_remove   -- copies beyond the first
FROM (
    SELECT date, premise_code, item_code, price, COUNT(*) AS n
    FROM staging.raw_price
    GROUP BY date, premise_code, item_code, price
    HAVING COUNT(*) > 1
) AS dups;

-- Result (build run): 0 duplicated groups, 0 extra rows.
