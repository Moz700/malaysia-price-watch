/* =====================================================================
   core.dim_festival and core.dim_date
   ---------------------------------------------------------------------
   dim_festival: the festival dates inside the study window, as observed
   in Malaysia (from the official public holiday announcements):
     Deepavali 2025              Mon 20 Oct 2025
     Chinese New Year 2026       Tue 17 Feb 2026
     Ramadan (1st day of fasting) Thu 19 Feb 2026
     Hari Raya Aidilfitri 2026   Sat 21 Mar 2026
     Hari Raya Haji 2026         Wed 27 May 2026

   Note: in 2026 Chinese New Year, Ramadan and Hari Raya fell within five
   weeks of each other. Their "before" windows overlap, which matters
   when reading q21 and q22.

   dim_date: one row per calendar day, built with generate_series().
   ===================================================================== */

DROP TABLE IF EXISTS core.dim_festival CASCADE;
CREATE TABLE core.dim_festival (
    festival       TEXT PRIMARY KEY,
    festival_date  DATE NOT NULL
);

INSERT INTO core.dim_festival (festival, festival_date) VALUES
    ('Deepavali',            DATE '2025-10-20'),
    ('Chinese New Year',     DATE '2026-02-17'),
    ('Ramadan',              DATE '2026-02-19'),
    ('Hari Raya Aidilfitri', DATE '2026-03-21'),
    ('Hari Raya Haji',       DATE '2026-05-27');


DROP TABLE IF EXISTS core.dim_date CASCADE;
CREATE TABLE core.dim_date (
    date            DATE PRIMARY KEY,
    year            SMALLINT NOT NULL,
    month           SMALLINT NOT NULL,
    month_name      TEXT     NOT NULL,
    year_month      TEXT     NOT NULL,   -- '2025-10' sorts correctly as text
    month_start     DATE     NOT NULL,
    iso_week        SMALLINT NOT NULL,
    day_of_week     SMALLINT NOT NULL,   -- 1 = Monday ... 7 = Sunday
    day_name        TEXT     NOT NULL,
    is_weekend      BOOLEAN  NOT NULL,   -- Sat/Sun (Kedah, Kelantan, Terengganu use Fri/Sat)
    festive_period  TEXT                 -- e.g. 'Pre-Chinese New Year' for the 14 days before
);

INSERT INTO core.dim_date
SELECT
    d::date,
    EXTRACT(YEAR    FROM d),
    EXTRACT(MONTH   FROM d),
    TO_CHAR(d, 'FMMonth'),            -- FM removes padding spaces
    TO_CHAR(d, 'YYYY-MM'),
    DATE_TRUNC('month', d)::date,
    EXTRACT(WEEK    FROM d),
    EXTRACT(ISODOW  FROM d),
    TO_CHAR(d, 'FMDay'),
    EXTRACT(ISODOW  FROM d) IN (6, 7),
    -- For each day, find the nearest festival that is
    -- 1 to 14 days ahead. If none, the result is NULL (not festive).
    (SELECT 'Pre-' || f.festival
       FROM core.dim_festival AS f
      WHERE f.festival_date - d::date BETWEEN 1 AND 14
      ORDER BY f.festival_date
      LIMIT 1)
FROM generate_series(DATE '2025-10-01', DATE '2026-09-30', INTERVAL '1 day') AS d;

-- Check: 365 days, and how many fall in each festive window
SELECT COALESCE(festive_period, '(not festive)') AS festive_period,
       COUNT(*) AS days, MIN(date) AS from_date, MAX(date) AS to_date
FROM core.dim_date
GROUP BY festive_period
ORDER BY from_date;
