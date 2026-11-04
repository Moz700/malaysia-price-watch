/* =====================================================================
   q01 · National median price of each item, September 2026
   ---------------------------------------------------------------------
   Stakeholder : A. Consumer and policy analyst (KPDN)
   Question    : What is the typical (median) price of each item in
                 Malaysia in the latest month, September 2026?
   Method      : Use core.fact_premise_item_month, which holds one price per
                 shop per item per month, so every shop counts once (see
                 sql/03_model/06). Join item names, group by item, take the
                 median across shops with PERCENTILE_CONT(0.5). The median
                 is used because a few shops charging double barely move it.
   Answer      : 329 items were priced in Sep 2026. Medians: chicken
                 (standard) RM 9.40/kg, grade B eggs RM 15.30 per 30,
                 imported white rice (Faiza Emas) RM 31.99 per 10 kg,
                 coarse sugar RM 2.85/kg, packet cooking oil RM 2.50/kg.
   ===================================================================== */

-- Part 1. Every item priced in September 2026
SELECT
    i.item_code,
    i.item,
    i.unit,
    i.item_group_en,
    COUNT(*)                                                                    AS premises,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.price)::numeric, 2)     AS median_price_rm,
    MIN(m.price)                                                                AS cheapest_shop_rm,
    MAX(m.price)                                                                AS dearest_shop_rm
FROM core.fact_premise_item_month AS m
JOIN core.dim_item                AS i
  ON i.item_code = m.item_code
WHERE m.month = DATE '2026-09-01'
GROUP BY i.item_code, i.item, i.unit, i.item_group_en
ORDER BY i.item_group_en, i.item;

-- Part 2. The household staples most people ask about
SELECT
    i.item_code,
    i.item,
    i.unit,
    COUNT(*)                                                                    AS premises,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.price)::numeric, 2)     AS median_price_rm
FROM core.fact_premise_item_month AS m
JOIN core.dim_item                AS i
  ON i.item_code = m.item_code
WHERE m.month = DATE '2026-09-01'
  AND m.item_code IN (2066, 1, 2, 1110, 918, 1589, 1593, 129, 1564, 93, 103)
GROUP BY i.item_code, i.item, i.unit
ORDER BY i.item;

-- Part 3. How many items, and in which groups
SELECT i.item_group_en, COUNT(DISTINCT m.item_code) AS items_priced
FROM core.fact_premise_item_month AS m
JOIN core.dim_item AS i ON i.item_code = m.item_code
WHERE m.month = DATE '2026-09-01'
GROUP BY ROLLUP (i.item_group_en)
ORDER BY items_priced DESC;
