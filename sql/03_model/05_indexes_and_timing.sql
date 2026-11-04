/* =====================================================================
   Indexes, with a before/after timing test
   ---------------------------------------------------------------------
   EXPLAIN ANALYZE of three typical queries, before and after
   a composite index on fact_price (item_code, date) and an index on
   premise_code. Each query runs twice and the second (warm-cache)
   timing is the one reported, so both runs read data already in memory.
   ===================================================================== */

-- Start from "no extra indexes" so the test is repeatable
DROP INDEX IF EXISTS core.idx_fact_item_date;
DROP INDEX IF EXISTS core.idx_fact_premise;

-- ---------- BEFORE ---------------------------------------------------
-- Test 1: daily national median price of one item (chicken, standard) all year
EXPLAIN ANALYZE
SELECT date, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median_price
FROM core.fact_price
WHERE item_code = 1
GROUP BY date;

EXPLAIN ANALYZE                                           -- second run: reported timing
SELECT date, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median_price
FROM core.fact_price
WHERE item_code = 1
GROUP BY date;

-- Test 2: every price one premise reported all year
EXPLAIN ANALYZE
SELECT item_code, COUNT(*), AVG(price)
FROM core.fact_price
WHERE premise_code = 5274
GROUP BY item_code;

EXPLAIN ANALYZE                                           -- reported timing
SELECT item_code, COUNT(*), AVG(price)
FROM core.fact_price
WHERE premise_code = 5274
GROUP BY item_code;

-- Test 3: one item in one month (what a dashboard filter does)
EXPLAIN ANALYZE
SELECT premise_code, AVG(price)
FROM core.fact_price
WHERE item_code = 1 AND date >= DATE '2026-09-01' AND date < DATE '2026-10-01'
GROUP BY premise_code;

EXPLAIN ANALYZE                                           -- reported timing
SELECT premise_code, AVG(price)
FROM core.fact_price
WHERE item_code = 1 AND date >= DATE '2026-09-01' AND date < DATE '2026-10-01'
GROUP BY premise_code;

-- ---------- CREATE THE INDEXES ---------------------------------------
-- (item_code, date): serves "one item over time" questions.
-- Column order matters: the index is sorted by item first, then date,
-- so it helps WHERE item_code = ... (and item + date range), but NOT a
-- filter on date alone. (The primary key already starts with date.)
CREATE INDEX idx_fact_item_date ON core.fact_price (item_code, date);
CREATE INDEX idx_fact_premise   ON core.fact_price (premise_code);
ANALYZE core.fact_price;

-- ---------- AFTER ----------------------------------------------------
EXPLAIN ANALYZE
SELECT date, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median_price
FROM core.fact_price
WHERE item_code = 1
GROUP BY date;

EXPLAIN ANALYZE                                           -- reported timing
SELECT date, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) AS median_price
FROM core.fact_price
WHERE item_code = 1
GROUP BY date;

EXPLAIN ANALYZE
SELECT item_code, COUNT(*), AVG(price)
FROM core.fact_price
WHERE premise_code = 5274
GROUP BY item_code;

EXPLAIN ANALYZE                                           -- reported timing
SELECT item_code, COUNT(*), AVG(price)
FROM core.fact_price
WHERE premise_code = 5274
GROUP BY item_code;

-- Test 3: one item in one month (what a dashboard filter does)
EXPLAIN ANALYZE
SELECT premise_code, AVG(price)
FROM core.fact_price
WHERE item_code = 1 AND date >= DATE '2026-09-01' AND date < DATE '2026-10-01'
GROUP BY premise_code;

EXPLAIN ANALYZE                                           -- reported timing
SELECT premise_code, AVG(price)
FROM core.fact_price
WHERE item_code = 1 AND date >= DATE '2026-09-01' AND date < DATE '2026-10-01'
GROUP BY premise_code;

-- Size check: disk space taken by the table and its indexes
SELECT
    relname                                   AS object,
    pg_size_pretty(pg_relation_size(oid))     AS size
FROM pg_class
WHERE relname IN ('fact_price', 'pk_fact_price', 'idx_fact_item_date', 'idx_fact_premise')
ORDER BY pg_relation_size(oid) DESC;
