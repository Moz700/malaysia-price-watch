/* =====================================================================
   core.dim_premise: one row per shop / market
   ---------------------------------------------------------------------
   Clean-ups applied:
     - drop the placeholder row premise_code = -1 ("Unknown Premise")
     - TRIM() premise_type: the source has 'Pasar Basah ' (trailing space,
       338 premises) and 'Pasar Basah' (22 premises). Without TRIM they
       would show as two different premise types in every GROUP BY.
     - add premise_type_en (English label)
     - first_seen / last_seen / days_reported / reporting_pattern are left
       empty here and filled from the clean fact table at the end of
       04_fact_price.sql (quality check 7).
   ===================================================================== */

DROP TABLE IF EXISTS core.dim_premise CASCADE;

CREATE TABLE core.dim_premise (
    premise_code       INTEGER PRIMARY KEY,
    premise            TEXT NOT NULL,
    premise_type       TEXT,
    premise_type_en    TEXT,
    state              TEXT,
    district           TEXT,
    first_seen         DATE,      -- first day with a clean price
    last_seen          DATE,      -- last day with a clean price
    days_reported      INTEGER,
    reporting_pattern  TEXT       -- Full year / Joined late / Stopped early / ...
);

INSERT INTO core.dim_premise (premise_code, premise, premise_type, premise_type_en, state, district)
SELECT
    premise_code,
    TRIM(premise),
    TRIM(premise_type),
    CASE TRIM(premise_type)
        WHEN 'Pasar Raya / Supermarket' THEN 'Supermarket'
        WHEN 'Hypermarket'              THEN 'Hypermarket'
        WHEN 'Pasar Mini'               THEN 'Mini market'
        WHEN 'Kedai Runcit'             THEN 'Sundry shop'
        WHEN 'Pasar Basah'              THEN 'Wet market'
        WHEN 'Borong'                   THEN 'Wholesaler'
        WHEN 'Kedai Serbaneka'          THEN 'Convenience store'
        WHEN 'Restoran Melayu'          THEN 'Malay restaurant'
        WHEN 'Restoran India Muslim'    THEN 'Indian Muslim restaurant'
        WHEN 'Restoran Cina'            THEN 'Chinese restaurant'
        WHEN 'Medan Selera'             THEN 'Food court (Medan Selera)'
        WHEN 'Foodcourt'                THEN 'Food court'
        ELSE 'Other'
    END,
    TRIM(state),
    TRIM(district)
FROM staging.lookup_premise
WHERE premise_code > 0;          -- removes the -1 placeholder

-- Check: after TRIM there is one 'Wet market' line, not two
SELECT premise_type_en, COUNT(*) AS premises
FROM core.dim_premise
GROUP BY premise_type_en
ORDER BY premises DESC;
