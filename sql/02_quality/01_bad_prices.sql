/* =====================================================================
   Quality check 1: missing, zero, negative or impossible prices
   ---------------------------------------------------------------------
   Rule:   drop any row whose price is NULL or below RM 0.10.
   Why:    nothing on the PriceCatcher list (a kilo of vegetables, a can of
           drink, a sachet of spice) sells for under 10 sen, so a price of
           RM 0.01-0.09 is a data-entry error. This ABSOLUTE floor backs up
           the RELATIVE outlier rule in check 6: check 6 compares a price
           with its item's median, which fails when an item has almost no
           other prices to compare with (found: IKAN GELAMA, reported once
           all year, at RM 0.01).
   ===================================================================== */

SELECT
    COUNT(*)                                        AS rows_affected,
    COUNT(*) FILTER (WHERE price IS NULL)           AS null_price,
    COUNT(*) FILTER (WHERE price <= 0)              AS zero_or_negative,
    COUNT(*) FILTER (WHERE price > 0 AND price < 0.10) AS below_10_sen
FROM staging.raw_price
WHERE price IS NULL
   OR price < 0.10;
