/* =====================================================================
   q31 · Two extra KPIs for the report's KPI scorecard
   ---------------------------------------------------------------------
   Stakeholder : A. Consumer and policy analyst (KPDN)
   Question    : 31a. Do shops keep controlled items at the controlled
                 price? (coarse sugar ceiling RM 2.85/kg, packet cooking
                 oil RM 2.50/kg)
                 31b. What share of listed districts has 4+ reporting
                 shops (monitoring coverage), September 2026?
   Method      : 31a. one price per shop per month (monthly fact table);
                 share of shop-months at or below the controlled price.
                 31b. districts listed in dim_premise vs districts with
                 4 or more shops reporting in September 2026.
   Answer      : 99.95% of 34,609 shop-months at or below the controlled
                 price (oil 99.94%, sugar 99.96%). 136 of 178 listed
                 districts (76.4%) had 4+ reporting shops in Sep 2026.
   ===================================================================== */

-- 31a. Price-control adherence (item 918 = packet cooking oil, 1589 = coarse sugar)
SELECT item_code,
       COUNT(*)                                                                         AS shop_months,
       SUM((price > CASE WHEN item_code = 918 THEN 2.50 ELSE 2.85 END)::int)            AS above_controlled,
       ROUND(100.0 * AVG((price <= CASE WHEN item_code = 918 THEN 2.50 ELSE 2.85 END)::int), 2) AS pct_at_or_below
FROM core.fact_premise_item_month
WHERE item_code IN (918, 1589)
GROUP BY item_code
UNION ALL
SELECT 0, COUNT(*),
       SUM((price > CASE WHEN item_code = 918 THEN 2.50 ELSE 2.85 END)::int),
       ROUND(100.0 * AVG((price <= CASE WHEN item_code = 918 THEN 2.50 ELSE 2.85 END)::int), 2)
FROM core.fact_premise_item_month
WHERE item_code IN (918, 1589);

-- 31b. Monitoring coverage, September 2026
WITH reporting AS (
    SELECT p.state, p.district, COUNT(DISTINCT m.premise_code) AS shops
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p USING (premise_code)
    WHERE m.month = DATE '2026-09-01'
    GROUP BY p.state, p.district
),
listed AS (
    SELECT DISTINCT state, district FROM core.dim_premise
    WHERE state IS NOT NULL AND district IS NOT NULL
)
SELECT (SELECT COUNT(*) FROM listed)                        AS districts_listed,
       (SELECT COUNT(*) FROM reporting)                     AS districts_reporting,
       (SELECT COUNT(*) FROM reporting WHERE shops >= 4)    AS districts_4plus,
       ROUND(100.0 * (SELECT COUNT(*) FROM reporting WHERE shops >= 4) / (SELECT COUNT(*) FROM listed), 1) AS coverage_pct;
