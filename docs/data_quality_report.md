# Data quality report

Seven checks ran on the 21,039,347 raw price rows before anything was analysed. Each check is its own file in `sql/02_quality/`; the rules are applied in `sql/03_model/04_fact_price.sql`, which writes every count to `core.data_quality_log`.

In total 316,802 of the 21,039,347 rows were removed (1.51%), leaving 20,722,545. Nearly all of the loss (313,598 rows) comes from one issue: item codes that the published item list does not yet contain.

## Rows removed, by rule

Each removed row is counted under exactly one rule, in the order the rules run.

| Step | Check | Rows | % of loaded | Action |
|---:|---|---:|---:|---|
| 0 | Rows loaded into staging | 21,039,347 | 100.000 | |
| 1 | Price missing or below RM 0.10 | 76 | 0.000 | dropped |
| 4 | Item code not in `lookup_item` | 313,598 | 1.491 | dropped |
| 5 | Premise code not in `lookup_premise` | 13 | 0.000 | dropped |
| 2, 3 | Duplicate or conflicting prices (same day, shop, item) | 0 | 0.000 | collapse to median |
| 6 | Outlier: above 5x or below 1/5 of the item's median for the month | 3,115 | 0.015 | dropped |
| 9 | **Rows in `core.fact_price`** | **20,722,545** | **98.494** | |

## The seven checks

### 1. Missing, zero, negative or impossible prices: 76 rows

- Rule: drop a price that is NULL or below RM 0.10.
- The data has no NULL, zero or negative prices, and 76 prices between RM 0.01 and RM 0.09.
- Nothing on the PriceCatcher list sells for under 10 sen, so these are entry errors. The absolute floor backs up the relative rule in check 6, which compares a price with its item's median and fails when an item has almost nothing to compare with: IKAN GELAMA was reported once all year, at RM 0.01, so it was its own median and passed the relative rule but not the floor.

### 2. Exact duplicate rows: 0 rows

- Rule: keep one copy of any row repeated on all four columns.
- None found. The check stays in the pipeline so that duplicates in a future month are caught.

### 3. One shop, one item, one day, two prices: 0 rows

- Rule: collapse to one row whose price is the median of the conflicting prices.
- A single typo (RM 4.50 vs RM 45.00) cannot move the median, and the fact table keeps exactly one row per (date, premise, item); the primary key on `core.fact_price` enforces that grain.
- None found.

### 4. Item codes missing from the item list: 313,598 rows

- Rule: drop prices whose `item_code` is not in `lookup_item`.
- 17 codes are missing, all between 2023 and 2096. The 12 largest were priced all year by 440 to 882 premises, so they are real, actively monitored items that the published lookup file does not list yet.
- Without a name, unit or category these prices cannot be compared, put in a basket or grouped.
- To recover them, re-download `lookup_item.csv`; if the codes appear, rerun `sql/run_all.sql` and the rows flow in automatically.

### 5. Premise codes missing from the premise list: 13 rows

- Rule: drop prices whose `premise_code` is not in `lookup_premise`.
- All 13 rows come from one premise (22280) that reported only on 25 and 26 Sep 2026, a new shop added at the very end of the period, before the lookup file included it.

### 6. Extreme outliers: 3,115 rows

- Rule: drop a price above 5x or below 1/5 of its item's national median for the same month. If the item has fewer than 20 reports that month, its full-year median is the yardstick instead, because in a thin month one odd price can itself be the median.
- The 5x and 0.2x limits are wide enough to keep real promotions and remote-area premiums, and tight enough to catch unit mix-ups (price per 100 g entered as per kg) and slips such as RM 7,985 for a 550 g tin of infant formula.
- The yardstick is a median because the outliers it looks for would drag an average with them.
- 367 outliers are too high and 2,748 too low. The most common are vegetables priced at RM 0.10 to 1.30 per kg against medians of RM 3 to 6 (mustard greens, tomato, pak choy, potatoes). Some may be real loss-leader promotions; removing them is the conservative choice, and at 0.015% of rows it does not move any result.
- The 15 most common patterns are in `results/build_run/04_quality_checks.txt`.

### 7. Premises that start late or stop early: kept and flagged

- Rule: keep the rows (the prices are real) and record each premise's `first_seen`, `last_seen`, `days_reported` and `reporting_pattern` in `core.dim_premise`.
- 2,028 premises report for the full year, 113 joined late, 110 stopped early and 11 did both (from `core.dim_premise`; the staging-level check shows 114 joining late because it also counts premise 22280, which is missing from the premise list).
- If cheap shops leave and dear shops join, an average rises with no shop changing a price. The year-on-year, pre-festival and CPI comparisons (q13, q14, q21, q27) therefore use matched shops: the same premise and item in both periods. The monthly and weekly trend lines (q17, q18, q20, q23) use each period's median across all reporting shops, which shows the shape of a trend but cannot measure an exact change. On the October 2025 to September 2026 comparison, the naive method (all shops in each month) misstated the change by more than 2 percentage points for 82 of 288 items (q13).

## Label fixes in the dimensions

Text fixes made while building the dimension tables; none of them removes a row.

| Issue | Fix | Where |
|---|---|---|
| `premise_type` has `'Pasar Basah '` (trailing space, 338 premises) and `'Pasar Basah'` (22): one type split in two | `TRIM()`; both become Wet market (360) | `03_model/02_dim_premise.sql` |
| Placeholder rows with code `-1` in both lookups (blank item; "Unknown Premise") | excluded from the dimensions; no price row uses them | `01_dim_item.sql`, `02_dim_premise.sql` |
| Malay labels only | English columns `premise_type_en`, `item_group_en` | `01_dim_item.sql`, `02_dim_premise.sql` |

## Reporting patterns that shape the method

Four collection patterns shaped the method.

1. Shops report at very different rates. In September 2026 a wet market reported each item about 15 times in the month, a supermarket 8, a mini market or sundry shop about 3. A median over raw rows lets frequent reporters outvote the rest: on September 2026 data it differed from the one-shop-one-vote median for 123 of 329 items, by more than 5% for 25 of them. `core.fact_premise_item_month` holds one price per shop per item per month, and every cross-shop comparison uses it.
2. Collection is concentrated on Mondays. 42.3% of all rows are Monday prices, as are 95.9% of sundry-shop and 92.3% of mini-market rows (September 2026). A public-holiday Monday therefore empties most of a week, so weekly series drop thin weeks and spike detection (q23) works on weekly prices instead of daily ones.
3. The data has no prices at all for 19 days, mostly public holidays (full list in `data_dictionary.md`).
4. Districts in Sabah and Sarawak are thinly covered. The two states have many premises overall, but in September 2026, 30 districts had only one to three reporting shops (22 of them in Sabah or Sarawak) and 12 listed districts had none (q06). Results for those districts rest on very few shops.

## Reproduce

```text
sql/02_quality/00_profile_columns.sql    column profiling
sql/02_quality/01_bad_prices.sql ... 07_premise_reporting_gaps.sql    the seven checks
sql/03_model/04_fact_price.sql           applies the rules, writes core.data_quality_log
SELECT * FROM core.data_quality_log ORDER BY step;
```
