/* =====================================================================
   Load the 15 CSV files into staging
   ---------------------------------------------------------------------
   psql script (\copy and \cd are psql meta-commands). \copy streams each
   file from the client, so the server needs no file-system access.

   Where the 15 CSVs are read from (datadir):
   - Default: the repo's data folder ("data"), where data/download.ps1
     and data/download.sh save the files. The path is relative to the
     folder psql is started from, so run psql from the repo root.
   - Override: pass any other folder with -v, using forward slashes:
       psql ... -v datadir="D:/my/folder" -f sql/01_load/01_load_all.sql
   ===================================================================== */

-- Folder that holds the 15 CSVs
\if :{?datadir}
\else
  \set datadir 'data'
\endif
\cd :datadir

-- Report the load time of each file
\timing on

-- Start clean so the script can be re-run without double-loading
TRUNCATE staging.raw_price, staging.lookup_item, staging.lookup_premise, ref.cpi_state;

-- Small lookup files
\copy staging.lookup_item    FROM 'lookup_item.csv'    WITH (FORMAT csv, HEADER true)
\copy staging.lookup_premise FROM 'lookup_premise.csv' WITH (FORMAT csv, HEADER true)
\copy ref.cpi_state          FROM 'cpi_2d_state.csv'   WITH (FORMAT csv, HEADER true)

-- 12 monthly price files (October 2025 to September 2026)
\copy staging.raw_price FROM 'pricecatcher_2025-10.csv' WITH (FORMAT csv, HEADER true)
\copy staging.raw_price FROM 'pricecatcher_2025-11.csv' WITH (FORMAT csv, HEADER true)
\copy staging.raw_price FROM 'pricecatcher_2025-12.csv' WITH (FORMAT csv, HEADER true)
\copy staging.raw_price FROM 'pricecatcher_2026-01.csv' WITH (FORMAT csv, HEADER true)
\copy staging.raw_price FROM 'pricecatcher_2026-02.csv' WITH (FORMAT csv, HEADER true)
\copy staging.raw_price FROM 'pricecatcher_2026-03.csv' WITH (FORMAT csv, HEADER true)
\copy staging.raw_price FROM 'pricecatcher_2026-04.csv' WITH (FORMAT csv, HEADER true)
\copy staging.raw_price FROM 'pricecatcher_2026-05.csv' WITH (FORMAT csv, HEADER true)
\copy staging.raw_price FROM 'pricecatcher_2026-06.csv' WITH (FORMAT csv, HEADER true)
\copy staging.raw_price FROM 'pricecatcher_2026-07.csv' WITH (FORMAT csv, HEADER true)
\copy staging.raw_price FROM 'pricecatcher_2026-08.csv' WITH (FORMAT csv, HEADER true)
\copy staging.raw_price FROM 'pricecatcher_2026-09.csv' WITH (FORMAT csv, HEADER true)

-- Refresh the planner's statistics so later queries pick good plans
ANALYZE staging.raw_price;

\timing off
