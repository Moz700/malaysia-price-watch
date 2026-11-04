/* =====================================================================
   q24 · How often does each premise change its price on the same item?
   ---------------------------------------------------------------------
   Stakeholder : B. Retail category manager
   Question    : Which shops re-price constantly (dynamic pricers) and
                 which hold prices steady? Which formats behave which way?
   Method      : For every (premise, item) series, LAG() gives the price at
                 that shop's previous report. A "change" is any report where
                 the price differs from the previous one. Change rate =
                 changes / comparisons. Full year.
   Read with care: wet markets report an item ~15 times a month, sundry
                 shops ~3 (once a week). A longer gap gives a price more
                 time to change, so per-report rates FLATTER weekly
                 reporters. Sundry shops still change least, so their
                 stickiness is real, not an artefact.
   Runtime     : ~2.5 minutes (a window over all 20.7 million rows)
   Answer      : Wet markets change price on 20.2% of reports,
                 hypermarkets 14.8%, supermarkets 13.4%, mini markets
                 13.3%, sundry shops 9.8%. Rises are about half of all
                 changes in every format. Of the 254,510 shop-item series
                 with 10+ reports, 30.7% never changed price all year.
   ===================================================================== */

DROP TABLE IF EXISTS series_change;
CREATE TEMP TABLE series_change AS              -- one row per (premise, item) series
WITH seq AS (
    SELECT premise_code, item_code, price,
           LAG(price) OVER (PARTITION BY premise_code, item_code ORDER BY date) AS prev_price
    FROM core.fact_price
)
SELECT premise_code, item_code,
       COUNT(prev_price)                            AS comparisons,   -- COUNT skips NULLs (first report)
       COUNT(*) FILTER (WHERE price <> prev_price)  AS changes,
       COUNT(*) FILTER (WHERE price >  prev_price)  AS increases
FROM seq
GROUP BY premise_code, item_code;

-- 24a. By premise type (premises with 100+ comparisons)
WITH by_premise AS (
    SELECT premise_code, SUM(comparisons) AS comparisons, SUM(changes) AS changes, SUM(increases) AS increases
    FROM series_change GROUP BY premise_code
)
SELECT p.premise_type_en,
       COUNT(*)                                                          AS premises,
       ROUND(100.0 * SUM(b.changes) / SUM(b.comparisons), 1)             AS pct_reports_with_change,
       ROUND(100.0 * SUM(b.increases) / NULLIF(SUM(b.changes), 0), 1)    AS pct_of_changes_that_are_rises
FROM by_premise       AS b
JOIN core.dim_premise AS p ON p.premise_code = b.premise_code
WHERE b.comparisons >= 100
GROUP BY p.premise_type_en
ORDER BY pct_reports_with_change DESC;

-- 24b. The most and least frequent re-pricers (shops with 1,000+ comparisons)
WITH by_premise AS (
    SELECT premise_code, SUM(comparisons) AS comparisons, SUM(changes) AS changes
    FROM series_change GROUP BY premise_code
)
(SELECT 'Most frequent' AS grp, p.premise, p.premise_type_en, p.state,
        ROUND(100.0 * b.changes / b.comparisons, 1) AS pct_reports_with_change
 FROM by_premise AS b JOIN core.dim_premise AS p ON p.premise_code = b.premise_code
 WHERE b.comparisons >= 1000
 ORDER BY b.changes::numeric / b.comparisons DESC
 LIMIT 5)
UNION ALL
(SELECT 'Least frequent', p.premise, p.premise_type_en, p.state,
        ROUND(100.0 * b.changes / b.comparisons, 1)
 FROM by_premise AS b JOIN core.dim_premise AS p ON p.premise_code = b.premise_code
 WHERE b.comparisons >= 1000
 ORDER BY b.changes::numeric / b.comparisons ASC
 LIMIT 5);

-- 24c. By item group: which goods are re-priced most?
SELECT i.item_group_en,
       ROUND(100.0 * SUM(s.changes) / SUM(s.comparisons), 1) AS pct_reports_with_change
FROM series_change AS s
JOIN core.dim_item AS i ON i.item_code = s.item_code
GROUP BY i.item_group_en
ORDER BY pct_reports_with_change DESC;

-- 24d. Share of (shop, item) series that never changed price all year
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE changes = 0) / COUNT(*), 1) AS pct_series_never_changed,
       COUNT(*)                                                         AS series_with_10plus_reports
FROM series_change
WHERE comparisons >= 10;
