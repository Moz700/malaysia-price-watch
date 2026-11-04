/* =====================================================================
   Quality check 6: extreme price outliers
   ---------------------------------------------------------------------
   Rule:   drop a price that is MORE than 5x, or LESS than 1/5 of, that
           item's national median price for the same month. If the item has
           fewer than 20 reports that month, its full-year median is used,
           because in a thin month one odd price can itself be the median.
   Why:    5x / 0.2x is wide enough to keep genuine promotions and remote
           -area premiums, but catches unit mix-ups (price per 100 g typed
           as per kg) and typing slips (7985 instead of 7.98).
           The median is used, not the average, because the outliers we
           are hunting would themselves drag an average around.
   Order:  measured only on rows that already passed checks 1-5, so each
           removed row is counted under exactly one check.
   ===================================================================== */

WITH valid AS (                                  -- rows that passed checks 1-5
    SELECT r.*
    FROM staging.raw_price AS r
    WHERE r.price >= 0.10
      AND EXISTS (SELECT 1 FROM staging.lookup_item    i WHERE i.item_code    = r.item_code)
      AND EXISTS (SELECT 1 FROM staging.lookup_premise p WHERE p.premise_code = r.premise_code)
),
item_month_median AS (                           -- one yardstick per item per month
    SELECT m.item_code, m.month,
           CASE WHEN m.n >= 20 THEN m.month_median ELSE y.year_median END AS median_price
    FROM (SELECT item_code, DATE_TRUNC('month', date)::date AS month, COUNT(*) AS n,
                 PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS month_median
          FROM valid GROUP BY item_code, DATE_TRUNC('month', date)) AS m
    JOIN (SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS year_median
          FROM valid GROUP BY item_code) AS y
      ON y.item_code = m.item_code
)
SELECT
    COUNT(*) FILTER (WHERE v.price > 5   * m.median_price) AS rows_above_5x,
    COUNT(*) FILTER (WHERE v.price < 0.2 * m.median_price) AS rows_below_one_fifth,
    COUNT(*) FILTER (WHERE v.price > 5   * m.median_price
                        OR v.price < 0.2 * m.median_price) AS rows_affected
FROM valid AS v
JOIN item_month_median AS m
  ON m.item_code = v.item_code
 AND m.month     = DATE_TRUNC('month', v.date)::date;

-- What do they look like? The 15 most common outlier patterns.
WITH valid AS (
    SELECT r.*
    FROM staging.raw_price AS r
    WHERE r.price >= 0.10
      AND EXISTS (SELECT 1 FROM staging.lookup_item    i WHERE i.item_code    = r.item_code)
      AND EXISTS (SELECT 1 FROM staging.lookup_premise p WHERE p.premise_code = r.premise_code)
),
item_month_median AS (                           -- one yardstick per item per month
    SELECT m.item_code, m.month,
           CASE WHEN m.n >= 20 THEN m.month_median ELSE y.year_median END AS median_price
    FROM (SELECT item_code, DATE_TRUNC('month', date)::date AS month, COUNT(*) AS n,
                 PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS month_median
          FROM valid GROUP BY item_code, DATE_TRUNC('month', date)) AS m
    JOIN (SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS year_median
          FROM valid GROUP BY item_code) AS y
      ON y.item_code = m.item_code
)
SELECT
    i.item,
    i.unit,
    CASE WHEN v.price > 5 * m.median_price THEN 'too high' ELSE 'too low' END AS direction,
    COUNT(*)                         AS rows,
    ROUND(AVG(m.median_price)::numeric, 2) AS typical_median,
    MIN(v.price)                     AS min_flagged_price,
    MAX(v.price)                     AS max_flagged_price
FROM valid AS v
JOIN item_month_median AS m
  ON m.item_code = v.item_code
 AND m.month     = DATE_TRUNC('month', v.date)::date
JOIN staging.lookup_item AS i
  ON i.item_code = v.item_code
WHERE v.price > 5 * m.median_price
   OR v.price < 0.2 * m.median_price
GROUP BY i.item, i.unit, direction
ORDER BY rows DESC
LIMIT 15;
