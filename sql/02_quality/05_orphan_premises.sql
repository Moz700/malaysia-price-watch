/* =====================================================================
   Quality check 5: prices from premises missing from lookup_premise
   ---------------------------------------------------------------------
   Rule:   drop price rows whose premise_code is not in lookup_premise.
   Why:    no state, district or premise type means the row cannot be
           used in any regional or shop-type comparison.
   ===================================================================== */

SELECT
    r.premise_code,
    COUNT(*)    AS rows_affected,
    MIN(r.date) AS first_seen,
    MAX(r.date) AS last_seen
FROM staging.raw_price AS r
WHERE NOT EXISTS (
    SELECT 1
    FROM staging.lookup_premise AS p
    WHERE p.premise_code = r.premise_code
)
GROUP BY r.premise_code;

-- Result (build run): 13 rows, one premise (22280), 25-26 Sep 2026 only:
-- a new shop added at the very end of the period, before the lookup file.
