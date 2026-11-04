/* =====================================================================
   q18 · Rolling 4-week average price for five staples
   ---------------------------------------------------------------------
   Stakeholder : C. Procurement / supply chain analyst
   Question    : What is the underlying trend for rice, chicken, eggs,
                 cooking oil and sugar, with the day-to-day noise smoothed?
   Items       : rice      BERAS PUTIH CAP FAIZA EMAS (IMPORT) 10 kg (code 2066,
                           the most widely priced rice item)
                 chicken   AYAM BERSIH - STANDARD 1 kg    (code 1)
                 eggs      TELUR AYAM GRED B, 30 eggs     (code 1110, the most
                           widely priced egg item)
                 oil       MINYAK MASAK PAKET 1 kg        (code 918, subsidised)
                 sugar     GULA PUTIH BERTAPIS KASAR 1 kg (code 1589)
   Method      : weekly national median (each shop's weekly average, then the
                 median across shops), then a rolling average of this week
                 and the 3 before it. Most mini markets and sundry shops are
                 surveyed once a week, on Mondays, so in a week whose Monday
                 is a public holiday only a handful of shops report (rice:
                 2-14 shops instead of ~750). Weeks with fewer than 100
                 reporting shops are dropped.
   Answer      : Smoothed 4-week range over the year: grade B eggs 50.5%
                 (RM 10.10-15.20), chicken 18.0%, imported rice 8.8%,
                 sugar and packet oil 0.0% (price-controlled).
   ===================================================================== */

WITH premise_week AS (
    SELECT item_code, premise_code, DATE_TRUNC('week', date)::date AS week_start, AVG(price) AS p
    FROM core.fact_price
    WHERE item_code IN (2066, 1, 1110, 918, 1589)
    GROUP BY item_code, premise_code, DATE_TRUNC('week', date)
),
item_week AS (
    SELECT item_code, week_start,
           COUNT(*)                                          AS premises,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p)    AS weekly_median
    FROM premise_week
    GROUP BY item_code, week_start
    HAVING COUNT(*) >= 100        -- drop holiday weeks when most shops did not report
)
SELECT
    i.item,
    w.week_start,
    w.premises,
    ROUND(w.weekly_median::numeric, 2)                                        AS weekly_median_rm,
    ROUND(AVG(w.weekly_median) OVER (
            PARTITION BY w.item_code
            ORDER BY w.week_start
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW)::numeric, 2)            AS rolling_4wk_avg_rm
FROM item_week     AS w
JOIN core.dim_item AS i ON i.item_code = w.item_code
ORDER BY i.item, w.week_start;

-- Summary: range of the smoothed line over the year, per item
WITH premise_week AS (
    SELECT item_code, premise_code, DATE_TRUNC('week', date)::date AS week_start, AVG(price) AS p
    FROM core.fact_price
    WHERE item_code IN (2066, 1, 1110, 918, 1589)
    GROUP BY item_code, premise_code, DATE_TRUNC('week', date)
),
item_week AS (
    SELECT item_code, week_start, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p) AS weekly_median
    FROM premise_week GROUP BY item_code, week_start
    HAVING COUNT(*) >= 100
),
smooth AS (
    SELECT item_code, week_start,
           AVG(weekly_median) OVER (PARTITION BY item_code ORDER BY week_start
                                    ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS r4
    FROM item_week
)
SELECT i.item,
       ROUND(MIN(r4)::numeric, 2)                         AS lowest_rm,
       ROUND(MAX(r4)::numeric, 2)                         AS highest_rm,
       ROUND(((MAX(r4) / MIN(r4) - 1) * 100)::numeric, 1) AS range_pct,
       (ARRAY_AGG(week_start ORDER BY r4 DESC))[1]        AS peak_week
FROM smooth AS s JOIN core.dim_item AS i ON i.item_code = s.item_code
WHERE s.week_start >= DATE '2025-10-20'          -- skip the first 3 weeks (window not yet full)
GROUP BY i.item
ORDER BY range_pct DESC;
