/* =====================================================================
   q21 · Do festive staples get dearer in the 2 weeks before each festival?
   ---------------------------------------------------------------------
   Stakeholder : C. Procurement / supply chain analyst
   Question    : Compare prices in the 14 days before each festival with
                 the 4 weeks before that (days -42 to -15). Do festive
                 staples rise, and by more than everything else?
   Staples     : chicken, meat, eggs, coconut (fresh and boxed santan),
                 onions/garlic, and fresh chillies.
   Method      : MATCHED pairs again: a (shop, item) counts only if it was
                 priced in both windows, so the change is real, not a change
                 in which shops reported. Each pair: pre-festival average /
                 baseline average - 1. Then, per festival, the MEAN and the
                 MEDIAN pair change for staples vs all other items (the
                 "control"). Most shops do not change a price within a few
                 weeks, so the median is usually 0; the mean shows which way
                 the prices that did move went. If staples rise and the
                 control does not, the festival is the likely cause rather
                 than general inflation.
   Caveats     : Data starts 1 Oct 2025, so the Deepavali baseline is only
                 1-5 Oct. Chinese New Year (17 Feb) and the start of Ramadan
                 (19 Feb) were 2 days apart, so their windows nearly
                 coincide: read them as one result. Hari Raya Aidilfitri
                 came 5 weeks after CNY, so its baseline overlaps both.
   Answer      : Most shop prices did not move (median pair change 0.00
                 for every festival). On average, festive staples fell
                 before Chinese New Year (-2.4%) and the start of Ramadan
                 (-2.6%; the two windows nearly coincide) and before Hari
                 Raya Aidilfitri (-5.0%), more than other items (-1.2%,
                 -1.2%, -0.5%). Before Hari Raya Haji staples rose 1.0%
                 vs 1.5% for other items.
   ===================================================================== */

DROP TABLE IF EXISTS festive_pairs;
CREATE TEMP TABLE festive_pairs AS
WITH staple_items AS (
    SELECT item_code
    FROM core.dim_item
    WHERE item_category IN ('AYAM', 'DAGING', 'TELUR', 'KELAPA', 'BAWANG', 'SANTAN (KOTAK)')
       OR item_code IN (92, 93, 94, 716, 1925, 1926, 1927)          -- fresh chillies
),
windows AS (                                       -- two date windows per festival
    SELECT festival, festival_date,
           festival_date - 14 AS pre_start,  festival_date - 1  AS pre_end,
           festival_date - 42 AS base_start, festival_date - 15 AS base_end
    FROM core.dim_festival
),
priced AS (                                        -- every price, tagged with the window it falls in
    SELECT w.festival, f.premise_code, f.item_code,
           CASE WHEN f.date BETWEEN w.pre_start  AND w.pre_end  THEN 'pre'
                WHEN f.date BETWEEN w.base_start AND w.base_end THEN 'base' END AS win,
           f.price
    FROM windows AS w
    JOIN core.fact_price AS f
      ON f.date BETWEEN w.base_start AND w.pre_end
)
SELECT festival, premise_code, item_code,
       item_code IN (SELECT item_code FROM staple_items)          AS is_staple,
       AVG(price) FILTER (WHERE win = 'pre')                       AS pre_avg,
       AVG(price) FILTER (WHERE win = 'base')                      AS base_avg
FROM priced
GROUP BY festival, premise_code, item_code
HAVING COUNT(*) FILTER (WHERE win = 'pre')  > 0                   -- matched: present in both
   AND COUNT(*) FILTER (WHERE win = 'base') > 0;

-- 21a. Staples vs everything else, per festival
SELECT
    d.festival,
    d.festival_date,
    CASE WHEN p.is_staple THEN 'Festive staples' ELSE 'All other items (control)' END AS item_set,
    COUNT(*)                                                                         AS matched_pairs,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.pre_avg / p.base_avg - 1) * 100)::numeric, 2) AS median_change_pct,
    ROUND((AVG(p.pre_avg / p.base_avg - 1) * 100)::numeric, 2)                        AS mean_change_pct,
    ROUND(100.0 * AVG(CASE WHEN p.pre_avg > p.base_avg THEN 1 ELSE 0 END), 1)         AS pct_pairs_up,
    ROUND(100.0 * AVG(CASE WHEN p.pre_avg < p.base_avg THEN 1 ELSE 0 END), 1)         AS pct_pairs_down
FROM festive_pairs     AS p
JOIN core.dim_festival AS d ON d.festival = p.festival
GROUP BY d.festival, d.festival_date, p.is_staple
ORDER BY d.festival_date, p.is_staple DESC;

-- 21b. Staple items with the biggest pre-festival rise (30+ matched shops)
SELECT
    p.festival,
    i.item,
    COUNT(*)                                                                         AS matched_pairs,
    ROUND((AVG(p.pre_avg / p.base_avg - 1) * 100)::numeric, 1)                        AS mean_change_pct,
    ROUND(100.0 * AVG(CASE WHEN p.pre_avg > p.base_avg THEN 1 ELSE 0 END), 0)         AS pct_shops_up
FROM festive_pairs AS p
JOIN core.dim_item AS i ON i.item_code = p.item_code
WHERE p.is_staple
GROUP BY p.festival, i.item
HAVING COUNT(*) >= 30
ORDER BY mean_change_pct DESC
LIMIT 15;
