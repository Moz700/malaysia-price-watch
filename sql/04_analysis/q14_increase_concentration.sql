/* =====================================================================
   q14 · Are price increases concentrated in a few categories?
   ---------------------------------------------------------------------
   Stakeholder : C. Procurement / supply chain analyst
   Question    : Is the year's inflation broad-based, or driven by a handful
                 of categories?
   Method      : Matched Oct 2025 -> Sep 2026 item changes (same method as
                 q13). For each category: how many items rose, and what
                 share of all the year's item-level increases (sum of the
                 positive % changes) it accounts for.
   Answer      : Vegetables, onions/garlic/shallots and meat made 57.6%
                 of all increases with 17.0% of the items; the top nine
                 categories made 90.9%.
   ===================================================================== */

WITH oct AS (
    SELECT premise_code, item_code, price AS p
    FROM core.fact_premise_item_month
    WHERE month = DATE '2025-10-01'
),
sep AS (
    SELECT premise_code, item_code, price AS p
    FROM core.fact_premise_item_month
    WHERE month = DATE '2026-09-01'
),
item_change AS (
    SELECT o.item_code,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.p / o.p - 1) AS chg
    FROM oct AS o
    JOIN sep AS s ON s.premise_code = o.premise_code AND s.item_code = o.item_code
    GROUP BY o.item_code
    HAVING COUNT(*) >= 30
),
by_category AS (
    SELECT
        i.item_category,
        COUNT(*)                                   AS items,
        COUNT(*) FILTER (WHERE c.chg > 0.05)       AS items_up_5pct,
        COUNT(*) FILTER (WHERE c.chg < -0.05)      AS items_down_5pct,
        AVG(c.chg)                                 AS avg_change,
        SUM(GREATEST(c.chg, 0))                    AS sum_of_increases   -- only the positive part
    FROM item_change AS c
    JOIN core.dim_item AS i ON i.item_code = c.item_code
    GROUP BY i.item_category
)
SELECT
    item_category,
    items,
    items_up_5pct,
    items_down_5pct,
    ROUND(avg_change::numeric * 100, 1)                                              AS avg_change_pct,
    ROUND((100 * sum_of_increases / SUM(sum_of_increases) OVER ())::numeric, 1)      AS share_of_all_increases_pct,
    ROUND((100 * SUM(sum_of_increases) OVER (ORDER BY sum_of_increases DESC)
               / SUM(sum_of_increases) OVER ())::numeric, 1)                         AS cumulative_share_pct,
    ROUND(100.0 * items / SUM(items) OVER (), 1)                                     AS share_of_items_pct
FROM by_category
ORDER BY sum_of_increases DESC;
