/* =====================================================================
   run_all.sql · Rebuild the whole project in one go (about 15 minutes)
   ---------------------------------------------------------------------
   Prerequisite: database "pricewatch" exists (sql/00_setup/00_create_database.sql).
   From PowerShell, in the malaysia-price-watch folder (the repo root):

     & "C:\Program Files\PostgreSQL\<version>\bin\psql.exe" -U postgres -d pricewatch `
       -f "$PWD\sql\run_all.sql"

   From bash (Mac/Linux), in the repo root:

     psql -U postgres -d pricewatch -f "$PWD/sql/run_all.sql"

   The CSVs are read from the repo's data folder by default. If they are
   somewhere else, add  -v datadir="<folder with the 15 CSVs, forward slashes>"

   Give -f the full path ($PWD\...): the load step changes psql's
   working folder to the data folder (\cd), and a full path keeps the
   remaining \ir steps findable. ON_ERROR_STOP makes psql halt at the
   first error instead of ploughing on.
   ===================================================================== */

\set ON_ERROR_STOP on
\timing on

\echo '== 00 setup'
\ir 00_setup/01_create_schemas.sql
\ir 00_setup/02_create_staging_tables.sql

\echo '== 01 load (about 30 seconds)'
\ir 01_load/01_load_all.sql
\ir 01_load/02_first_look.sql

\echo '== 03 model: dimensions'
\ir 03_model/01_dim_item.sql
\ir 03_model/02_dim_premise.sql
\ir 03_model/03_dim_date.sql

\echo '== 03 model: fact table with quality rules (about 5 minutes)'
\ir 03_model/04_fact_price.sql

\echo '== 03 model: indexes and timing test'
\ir 03_model/05_indexes_and_timing.sql

\echo '== 03 model: monthly aggregate fact (about 1 minute)'
\ir 03_model/06_fact_premise_item_month.sql

\echo '== 05 views (about 1 minute)'
\ir 05_views/01_create_views.sql

\echo '== Done. Quality checks (sql/02_quality) and analysis (sql/04_analysis) run one file at a time.'
