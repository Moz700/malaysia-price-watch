# Data quality report

Seven checks ran on the 21,039,347 raw price rows before anything was analysed. Each check is its own file in `sql/02_quality/`; the rules are applied in `sql/03_model/04_fact_price.sql`, which writes every count to `core.data_quality_log`.

**Result: 21,039,347 rows in, 20,722,545 rows out. 316,802 rows removed (1.51%).** Nearly all of the loss (313,598 rows) is one issue: item codes that the published item list does not yet contain.

## Rows removed, by rule

Each removed row is counted under exactly one rule, in the order the rules run.

| Step | Check | Rows | % of loaded | Action |
|---:|---|---:|---:|---|
| 0 | Rows loaded into staging | 21,039,347 | 100.000 | |
| 1 | Price missing or below RM 0.10 | 76 | 0.000 | dropped |
| 4 | Item code not in `lookup_item` | 313,598 | 1.491 | dropped |
| 5 | Premise code not in `lookup_premise` | 13 | 0.000 | dropped |
| 2–3 | Duplicate or conflicting prices (same day, shop, item) | 0 | 0.000 | collapse to median |
| 6 | Outlier: above 5x or below 1/5 of the item's median for the month | 3,115 | 0.015 | dropped |
| 9 | **Rows in `core.fact_price`** | **20,722,545** | **98.494** | |

## Each check, the rule and the reason

### 1. Missing, zero, negative or impossible prices: 76 rows

- **Rule:** drop a price that is NULL or below RM 0.10.
- **Found:** no NULL, zero or negative prices; 76 prices between RM 0.01 and RM 0.09.
- **Why 10 sen:** nothing on the PriceCatcher list sells for under 10 sen, so these are entry errors. This absolute floor backs up the relative rule in check 6, which compares a price with its item's median. That comparison fails when an item has almost nothing to compare with: IKAN GELAMA was reported once all year, at RM 0.01, so it was its own median and passed the relative rule. The floor catches it.

### 2. Exact duplicate rows: 0 rows

- **Rule:** keep one copy of any row repeated on all four columns.
- **Found:** none. The check stays in the pipeline so a future month cannot slip duplicates through.

### 3. One shop, one item, one day, two prices: 0 rows

- **Rule:** collapse to one row whose price is the median of the conflicting prices.
- **Why the median:** a single typo (RM 4.50 vs RM 45.00) cannot move it, and the fact table keeps exactly one row per (date, premise, item). The primary key on `core.fact_price` enforces that grain.
- **Found:** none.

### 4. Item codes missing from the item list: 313,598 rows

- **Rule:** drop prices whose `item_code` is not in `lookup_item`.
- **Found:** 17 codes, all in the 2023–2096 range. The 12 largest were priced all year by 440 to 882 premises, so they are real, actively monitored items that the published lookup file has not caught up with.
- **Why drop:** with no name, unit or category they cannot be compared, put in a basket or grouped.
- **Fix later:** re-download `lookup_item.csv`; if the codes appear, rerun `sql/run_all.sql` and the rows flow in automatically.

### 5. Premise codes missing from the premise list: 13 rows

- **Rule:** drop prices whose `premise_code` is not in `lookup_premise`.
- **Found:** one premise (22280), reporting only on 25–26 Sep 2026: a new shop added at the very end of the period, before the lookup file.

### 6. Extreme outliers: 3,115 rows

- **Rule:** drop a price above 5x or below 1/5 of its item's national median for the same month. If the item has fewer than 20 reports that month, its full-year median is the yardstick instead, because in a thin month one odd price can itself be the median.
- **Why 5x / 0.2x:** wide enough to keep real promotions and remote-area premiums, tight enough to catch unit mix-ups (price per 100 g entered as per kg) and slips such as RM 7,985 for a 550 g tin of infant formula.
- **Why the median:** the outliers being hunted would drag an average with them.
- **What they look like:** 367 are too high and 2,748 too low. The most common are "too low" vegetables at RM 0.10–1.30 per kg against medians of RM 3–6 (mustard greens, tomato, pak choy, potatoes). Some may be real loss-leader promotions; removing them is the conservative choice, and at 0.015% of rows it does not move any result.
- The 15 most common patterns: `results/build_run/04_quality_checks.txt`.

### 7. Premises that start late or stop early: flagged, not removed

- **Rule:** keep the rows (the prices are real), record each premise's `first_seen`, `last_seen`, `days_reported` and `reporting_pattern` in `core.dim_premise`.
- **Found:** 2,028 premises report for the full year, 113 joined late, 110 stopped early, 11 did both (from `core.dim_premise`; the staging-level check shows 114 joining late because it also counts premise 22280, which is missing from the premise list).
- **Why it matters:** if cheap shops leave and dear shops join, an average rises with no shop changing a price. The year-on-year, pre-festival and CPI comparisons (q13, q14, q21, q27) therefore use matched shops: the same premise and item in both periods. The monthly and weekly trend lines (q17, q18, q20, q23) use each period's median across all reporting shops, which is fine for showing the shape of a trend but not for measuring an exact change. On the October 2025 to September 2026 comparison, the naive method (all shops in each month) misstated the change by more than 2 percentage points for 82 of 288 items (q13).

## Clean-ups that change labels, not rows

Text fixes made while building the dimensions.

| Issue | Fix | Where |
|---|---|---|
| `premise_type` has `'Pasar Basah '` (trailing space, 338 premises) and `'Pasar Basah'` (22): one type split in two | `TRIM()`; both become Wet market (360) | `03_model/02_dim_premise.sql` |
| Placeholder rows with code `-1` in both lookups (blank item; "Unknown Premise") | excluded from the dimensions; no price row uses them | `01_dim_item.sql`, `02_dim_premise.sql` |
| Malay labels only | English columns `premise_type_en`, `item_group_en` | `01_dim_item.sql`, `02_dim_premise.sql` |

## Things that are not errors but change how the data must be read

These shaped the method more than any dropped row did.

1. **Shops report at very different rates.** In September 2026 a wet market reported each item about 15 times in the month, a supermarket 8, a mini market or sundry shop about 3. A median over raw rows lets frequent reporters outvote the rest: on September 2026 data it differed from the one-shop-one-vote median for 123 of 329 items, by more than 5% for 25 of them. `core.fact_premise_item_month` holds one price per shop per item per month, and every cross-shop comparison uses it.
2. **Collection is concentrated on Mondays.** 42.3% of all rows are Monday prices; 95.9% of sundry-shop and 92.3% of mini-market rows (September 2026). A public-holiday Monday therefore empties most of a week, so weekly series drop thin weeks and spike detection (q23) uses weeks, not days.
3. **19 days have no prices at all,** mostly public holidays (full list in `data_dictionary.md`).
4. **Districts in Sabah and Sarawak are thinly covered.** The two states have many premises overall, but 30 districts had 3 or fewer reporting shops in September 2026 and 22 of them are in Sabah or Sarawak (q06). Results for those districts rest on very few shops.

## Reproduce

```text
sql/02_quality/00_profile_columns.sql    column profiling
sql/02_quality/01_bad_prices.sql ... 07_premise_reporting_gaps.sql    the seven checks
sql/03_model/04_fact_price.sql           applies the rules, writes core.data_quality_log
SELECT * FROM core.data_quality_log ORDER BY step;
```
