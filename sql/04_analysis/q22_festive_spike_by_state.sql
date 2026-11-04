/* =====================================================================
   q22 · Which states see the biggest festive price spikes?
   ---------------------------------------------------------------------
   Stakeholder : A. Consumer and policy analyst (KPDN)
   Question    : Where should pre-festival price enforcement focus?
   Method      : Same matched festive-staple pairs as q21 (pre-festival 14
                 days vs the 4 weeks before), averaged by state. RANK() per
                 festival orders the states. Deepavali is left out because
                 its baseline is only 5 days (data starts 1 Oct 2025).
   Answer      : East Malaysia moved against the Peninsula: before CNY
                 staples rose only in Labuan (+1.85%) and Sabah (+0.35%);
                 before Hari Raya Aidilfitri Sabah fell least (-1.02%)
                 and Selangor most (-5.88%); before Hari Raya Haji,
                 Sabah, Sarawak and Labuan were the only states where
                 staples fell.
   ===================================================================== */

WITH staple_items AS (
    SELECT item_code FROM core.dim_item
    WHERE item_category IN ('AYAM', 'DAGING', 'TELUR', 'KELAPA', 'BAWANG', 'SANTAN (KOTAK)')
       OR item_code IN (92, 93, 94, 716, 1925, 1926, 1927)
),
windows AS (
    SELECT festival, festival_date,
           festival_date - 14 AS pre_start,  festival_date - 1  AS pre_end,
           festival_date - 42 AS base_start, festival_date - 15 AS base_end
    FROM core.dim_festival
    WHERE festival <> 'Deepavali'
),
pairs AS (
    SELECT w.festival, f.premise_code, f.item_code,
           AVG(f.price) FILTER (WHERE f.date BETWEEN w.pre_start  AND w.pre_end)  AS pre_avg,
           AVG(f.price) FILTER (WHERE f.date BETWEEN w.base_start AND w.base_end) AS base_avg
    FROM windows AS w
    JOIN core.fact_price AS f ON f.date BETWEEN w.base_start AND w.pre_end
    WHERE f.item_code IN (SELECT item_code FROM staple_items)
    GROUP BY w.festival, f.premise_code, f.item_code
),
by_state AS (
    SELECT pr.festival, p.state,
           COUNT(*)                                   AS matched_pairs,
           AVG(pr.pre_avg / pr.base_avg - 1)          AS mean_change
    FROM pairs AS pr
    JOIN core.dim_premise AS p ON p.premise_code = pr.premise_code
    WHERE pr.pre_avg IS NOT NULL AND pr.base_avg IS NOT NULL
    GROUP BY pr.festival, p.state
)
SELECT
    festival,
    state,
    matched_pairs,
    ROUND((mean_change * 100)::numeric, 2)                                 AS staple_change_pct,
    RANK() OVER (PARTITION BY festival ORDER BY mean_change DESC)          AS rank_in_festival
FROM by_state
ORDER BY festival, rank_in_festival;
