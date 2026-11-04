/* =====================================================================
   q27 · Sense check: do PriceCatcher food prices move with CPI food (division 01)?
   ---------------------------------------------------------------------
   Stakeholder : All
   Question    : Month by month and state by state, does a food price
                 index built from PriceCatcher move in the same direction
                 as DOSM's official CPI for Food & Non-Alcoholic Beverages?
   OFFICIAL CAVEAT: data.gov.my states PriceCatcher is built for price
                 SURVEILLANCE, not for measuring inflation; DOSM's CPI is the
                 official measure. This query is a CONSISTENCY CHECK only.
                 It is not an inflation estimate.
   Method      : 1) food items only (no household/hygiene, no diapers)
                 2) each shop's monthly price per item (fact_premise_item_month)
                 3) month-on-month change per (shop, item) present in both
                    months (matched), combined per state as a geometric mean:
                    EXP(AVG(LN(price ratio))). This "Jevons" formula is what
                    statistics offices use for the lowest level of a CPI.
                 4) join to CPI division '01' month-on-month change per state
                 5) CORR() = Pearson correlation, -1 to +1
                 CPI data ends August 2026, so months are Nov 2025 - Aug 2026.
   Answer      : PriceCatcher food and CPI food month-on-month changes
                 correlate at 0.60 over 160 state-months. Oct 2025-Aug
                 2026 cumulative: PriceCatcher -2.4% to +2.0% by state,
                 CPI +0.1% to +2.7%; Sabah and Labuan diverge most.
   ===================================================================== */

DROP TABLE IF EXISTS pc_vs_cpi;
CREATE TEMP TABLE pc_vs_cpi AS
WITH food_items AS (                                                         -- step 1
    SELECT item_code FROM core.dim_item
    WHERE item_group_en NOT IN ('Household and hygiene')
      AND item_category <> 'LAMPIN PAKAI BUANG'
),
shop_month AS (                                                              -- step 2
    SELECT p.state, m.premise_code, m.item_code, m.month, m.price AS p
    FROM core.fact_premise_item_month AS m
    JOIN core.dim_premise             AS p ON p.premise_code = m.premise_code
    WHERE m.item_code IN (SELECT item_code FROM food_items)
),
pc_state_mom AS (                                                            -- step 3
    SELECT cur.state, cur.month,
           COUNT(*)                          AS matched_pairs,
           EXP(AVG(LN(cur.p / prev.p))) - 1  AS pc_mom
    FROM shop_month AS cur
    JOIN shop_month AS prev
      ON prev.premise_code = cur.premise_code
     AND prev.item_code    = cur.item_code
     AND prev.month        = (cur.month - INTERVAL '1 month')::date
    GROUP BY cur.state, cur.month
),
cpi_mom AS (                                                                 -- step 4
    SELECT state, date AS month,
           index / LAG(index) OVER (PARTITION BY state ORDER BY date) - 1 AS cpi_mom
    FROM ref.cpi_state
    WHERE division = '01'
)
SELECT pc.state, pc.month, pc.matched_pairs, pc.pc_mom, c.cpi_mom
FROM pc_state_mom AS pc
JOIN cpi_mom      AS c ON c.state = pc.state AND c.month = pc.month;

-- 27a. Correlation, all states and months pooled                               step 5
SELECT COUNT(*)                                           AS state_months,
       ROUND(CORR(pc_mom, cpi_mom)::numeric, 2)           AS correlation,
       ROUND(100.0 * AVG(CASE WHEN SIGN(pc_mom) = SIGN(cpi_mom) THEN 1 ELSE 0 END), 1) AS pct_same_direction
FROM pc_vs_cpi;

-- 27b. National picture: average across states, month by month
SELECT month,
       ROUND((AVG(pc_mom)  * 100)::numeric, 2) AS pricecatcher_food_mom_pct,
       ROUND((AVG(cpi_mom) * 100)::numeric, 2) AS cpi_food_mom_pct
FROM pc_vs_cpi
GROUP BY month
ORDER BY month;

-- 27c. Cumulative Oct 2025 -> Aug 2026, by state (chain the monthly changes)
SELECT state,
       ROUND(((EXP(SUM(LN(1 + pc_mom)))  - 1) * 100)::numeric, 1) AS pricecatcher_food_cum_pct,
       ROUND(((EXP(SUM(LN(1 + cpi_mom))) - 1) * 100)::numeric, 1) AS cpi_food_cum_pct,
       ROUND(CORR(pc_mom, cpi_mom)::numeric, 2)                    AS monthly_correlation
FROM pc_vs_cpi
GROUP BY state
ORDER BY pricecatcher_food_cum_pct DESC;
