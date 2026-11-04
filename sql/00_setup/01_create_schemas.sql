/* =====================================================================
   Create the four schemas (connected to database "pricewatch")
   ---------------------------------------------------------------------
   Four schemas, one per stage of the pipeline, so raw data never gets
   mixed up with cleaned data:

     staging : raw CSVs loaded exactly as they arrive (never edited)
     ref     : outside reference data (DOSM CPI by state)
     core    : cleaned star schema (dimensions + fact tables)
     mart    : views that answer business questions and feed Power BI

   Why separate staging from core? If a cleaning rule turns out to be
   wrong, the untouched raw data is still in staging, so core can be
   rebuilt without downloading anything again.
   ===================================================================== */

CREATE SCHEMA IF NOT EXISTS staging;   -- safe to re-run
CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS mart;

-- Check: list the four schemas
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('staging', 'ref', 'core', 'mart')
ORDER BY schema_name;
