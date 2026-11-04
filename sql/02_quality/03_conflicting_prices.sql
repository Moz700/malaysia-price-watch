/* =====================================================================
   Quality check 3: one shop, one item, one day, two prices
   ---------------------------------------------------------------------
   Rule:   if a premise reports more than one price for the same item on
           the same day, keep one row whose price is the median of those
           prices.
   Why:    the median is not pulled by a single typo (RM 4.50 vs RM 45.00),
           and it keeps the grain of the fact table at exactly one row per
           (date, premise, item), which the primary key then enforces.
   ===================================================================== */

SELECT
    COUNT(*)                                   AS keys_with_more_than_one_row,
    COUNT(*) FILTER (WHERE distinct_prices > 1) AS keys_with_different_prices,
    COALESCE(SUM(n - 1), 0)                    AS extra_rows_collapsed
FROM (
    SELECT date, premise_code, item_code,
           COUNT(*)              AS n,
           COUNT(DISTINCT price) AS distinct_prices
    FROM staging.raw_price
    GROUP BY date, premise_code, item_code
    HAVING COUNT(*) > 1
) AS multi;

-- Result (build run): 0. Every (date, premise, item) already has one price.
-- The median rule is still written into the fact-table build so the
-- primary key can never be violated by a future file.
