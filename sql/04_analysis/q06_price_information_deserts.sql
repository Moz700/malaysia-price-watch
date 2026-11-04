/* =====================================================================
   q06 · Districts with the fewest reporting premises
   ---------------------------------------------------------------------
   Stakeholder : A. Consumer and policy analyst (KPDN)
   Question    : Where is price monitoring thinnest: districts where only
                 one or two shops report, so a price complaint there has
                 little evidence behind it ("price-information deserts")?
   Method      : September 2026 (current coverage). Count distinct
                 reporting premises per district; keep districts with 3 or
                 fewer.
   Answer      : 30 districts had 3 or fewer reporting shops in Sep 2026,
                 22 of them in Sabah or Sarawak; 12 listed districts
                 (e.g. Cameron Highlands, Kampar) had none.
   ===================================================================== */

-- 6a. The thin districts
SELECT
    p.state,
    p.district,
    COUNT(DISTINCT f.premise_code)  AS reporting_premises,
    COUNT(DISTINCT f.item_code)     AS items_priced,
    STRING_AGG(DISTINCT p.premise_type_en, ', ') AS premise_types   -- list types in one cell
FROM core.fact_price  AS f
JOIN core.dim_premise AS p ON p.premise_code = f.premise_code
WHERE f.date >= DATE '2026-09-01' AND f.date < DATE '2026-10-01'
GROUP BY p.state, p.district
HAVING COUNT(DISTINCT f.premise_code) <= 3
ORDER BY reporting_premises, items_priced;

-- 6b. How common is that? Districts by number of reporting premises.
WITH d AS (
    SELECT p.state, p.district, COUNT(DISTINCT f.premise_code) AS n
    FROM core.fact_price  AS f
    JOIN core.dim_premise AS p ON p.premise_code = f.premise_code
    WHERE f.date >= DATE '2026-09-01' AND f.date < DATE '2026-10-01'
    GROUP BY p.state, p.district
)
SELECT
    CASE WHEN n <= 3  THEN '1-3 premises'
         WHEN n <= 10 THEN '4-10 premises'
         WHEN n <= 25 THEN '11-25 premises'
         ELSE '26+ premises' END                AS district_band,
    COUNT(*)                                    AS districts
FROM d
GROUP BY 1
ORDER BY MIN(n);

-- 6c. Districts in the premise list that had NO reporting premise in September
SELECT p.state, p.district, COUNT(*) AS premises_listed
FROM core.dim_premise AS p
WHERE p.district IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM core.fact_price  AS f
        JOIN core.dim_premise AS p2 ON p2.premise_code = f.premise_code
        WHERE p2.state = p.state AND p2.district = p.district
          AND f.date >= DATE '2026-09-01' AND f.date < DATE '2026-10-01')
GROUP BY p.state, p.district
ORDER BY p.state, p.district;
