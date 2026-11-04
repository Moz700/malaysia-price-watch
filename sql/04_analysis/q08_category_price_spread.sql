/* =====================================================================
   q08 · Which item categories have the widest price range across Malaysia?
   ---------------------------------------------------------------------
   Stakeholder : C. Procurement / supply chain analyst
   Question    : In which categories does the same item sell at very
                 different prices from shop to shop?
   Method      : September 2026, one price per shop. For each item, the
                 coefficient of variation (CV) = STDDEV / AVG of its price
                 across shops. CV has no unit, so a RM 50 item and a RM 2
                 item can be compared. Then the average item CV per category.
                 (A raw STDDEV of a whole category would mostly measure that
                 the category mixes cheap and dear items, not shop-to-shop
                 spread.) Also P90/P10: how many times dearer the shop at the
                 90th percentile is than the shop at the 10th.
   Answer      : Widest shop-to-shop spread: dried seafood (average CV
                 40.3%) and vegetables (32.4%). Narrowest: rice (3.3%),
                 infant formula (5.3%), cooking oils (5.5%), eggs (5.8%).
   ===================================================================== */

WITH item_spread AS (
    SELECT
        item_code,
        COUNT(*)                                             AS premises,
        STDDEV(price) / AVG(price)                           AS cv,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY price)
      / PERCENTILE_CONT(0.1) WITHIN GROUP (ORDER BY price)   AS p90_p10
    FROM core.fact_premise_item_month
    WHERE month = DATE '2026-09-01'
    GROUP BY item_code
    HAVING COUNT(*) >= 30                                    -- enough shops to measure spread
)
SELECT
    i.item_group_en,
    i.item_category,
    COUNT(*)                                    AS items,
    ROUND(AVG(s.cv)::numeric * 100, 1)          AS avg_cv_pct,
    ROUND(AVG(s.p90_p10)::numeric, 2)           AS avg_p90_to_p10
FROM item_spread   AS s
JOIN core.dim_item AS i ON i.item_code = s.item_code
GROUP BY i.item_group_en, i.item_category
HAVING COUNT(*) >= 2
ORDER BY avg_cv_pct DESC;

-- The 10 single items with the widest spread
WITH item_spread AS (
    SELECT item_code,
           COUNT(*)                                            AS premises,
           STDDEV(price) / AVG(price)                          AS cv,
           PERCENTILE_CONT(0.1) WITHIN GROUP (ORDER BY price)  AS p10,
           PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY price)  AS p90
    FROM core.fact_premise_item_month
    WHERE month = DATE '2026-09-01'
    GROUP BY item_code
    HAVING COUNT(*) >= 30
)
SELECT i.item, i.unit, s.premises,
       ROUND(s.cv::numeric * 100, 1) AS cv_pct,
       ROUND(s.p10::numeric, 2)      AS p10_rm,
       ROUND(s.p90::numeric, 2)      AS p90_rm
FROM item_spread   AS s
JOIN core.dim_item AS i ON i.item_code = s.item_code
ORDER BY s.cv DESC
LIMIT 10;
