/* =====================================================================
   Staging tables (one per source file type)
   ---------------------------------------------------------------------
   Staging tables mirror the CSV columns exactly. No primary keys and no
   constraints yet: every raw row should load, good or bad, so the
   quality checks in sql/02_quality can count the problems.

   Data types:
     date          -> DATE
     codes         -> INTEGER         (-1 is used as "unknown")
     price         -> NUMERIC(10,2)   (exact decimal; see note below)
     text columns  -> TEXT

   Money is stored as NUMERIC, not FLOAT:
     FLOAT cannot hold values such as 0.10 exactly, so sums drift.
     NUMERIC keeps the exact decimal digits, so RM 10.60 stays RM 10.60.
     All source prices have at most 2 decimal places, so NUMERIC(10,2)
     loses nothing.
   ===================================================================== */

DROP TABLE IF EXISTS staging.raw_price;
CREATE TABLE staging.raw_price (
    date          DATE,
    premise_code  INTEGER,
    item_code     INTEGER,
    price         NUMERIC(10,2)
);

DROP TABLE IF EXISTS staging.lookup_item;
CREATE TABLE staging.lookup_item (
    item_code      INTEGER,
    item           TEXT,
    unit           TEXT,
    item_group     TEXT,
    item_category  TEXT
);

DROP TABLE IF EXISTS staging.lookup_premise;
CREATE TABLE staging.lookup_premise (
    premise_code  INTEGER,
    premise       TEXT,
    address       TEXT,
    premise_type  TEXT,
    state         TEXT,
    district      TEXT
);

-- CPI goes in "ref" because it is reference data from a different agency
-- (DOSM). division is TEXT because the file mixes '01'..'13' with 'overall'.
DROP TABLE IF EXISTS ref.cpi_state;
CREATE TABLE ref.cpi_state (
    state     TEXT,
    date      DATE,
    division  TEXT,
    index     NUMERIC(6,1)
);
