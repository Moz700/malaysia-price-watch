# Data lineage

The source of each number in the [README](../README.md), the dashboard KPI tiles and the Power BI KPI measures. `results/build_run/` holds the output of every script from the build run; derived figures show their arithmetic.

## The 6 headline KPIs

These appear in the README "Headline numbers" table, the dashboard KPI tiles (`dashboard/build_data.py`) and the Power BI `_Measures` table, folder KPI (`powerbi/MalaysiaPriceWatch.SemanticModel/definition/tables/_Measures.tmdl`).

| Number | What it is | Source (file and row) |
|---|---|---|
| 9.9% | Regional basket gap, Kuala Lumpur vs Kedah | `results/build_run/q09.txt`: 4,349.65 / 3,959.53 − 1 = 9.85%, shown as 9.9%. Also `q30.txt`. Power BI measure `Regional basket gap` = 0.099 |
| RM 4,349.65 | Basket cost, W.P. Kuala Lumpur, September 2026 | `q09.txt`, row W.P. Kuala Lumpur, `basket_cost_rm` (also `dashboard/data/state_basket.csv`) |
| RM 3,959.53 | Basket cost, Kedah | `q09.txt`, row Kedah (also `state_basket.csv`) |
| RM 390.12 | Kuala Lumpur minus Kedah | 4,349.65 − 3,959.53 (q09) |
| 265 | Items in the basket | `q09.txt`, column `basket_items` |
| 12.0% | Staples gap, wet market vs hypermarket | `q03.txt`, second table: 99.45 / 88.76 − 1 = 12.04%. Power BI measure `Staples gap, wet market vs hypermarket` = 0.12 |
| RM 99.45 | One unit of each of the 8 staples at wet markets | `q03.txt`, second table, sum of the `wet_market` column (8 rows) |
| RM 88.76 | The same at hypermarkets | `q03.txt`, second table, sum of the `hypermarket` column |
| 8 | Staples in that table | `q03.txt`, second table, "(8 rows)" |
| 99.95% | Price-control adherence | `q31.txt`, first table, row for both items together, `pct_at_or_below`. Power BI measure `Price-control adherence` = 0.9995 |
| 34,609 | Shop-months checked | `q31.txt`, same row, `shop_months` |
| RM 2.85, RM 2.50 | Controlled prices of coarse sugar and packet cooking oil | `sql/04_analysis/q31_kpi_checks.sql` header and `q03.txt` second table (both items at those prices in every format) |
| 58% | Share of all price increases from 3 categories | `q14.txt`, row DAGING, `cumulative_share_pct` 57.6, shown as 58%. Power BI measure `Share of price increases from 3 categories` = 0.58 |
| 17% | Share of items in those 3 categories | `q14.txt`, `share_of_items_pct`: 9.7 + 2.8 + 4.5 = 17.0 |
| 12.1 points | Gap to the price leader | 101.4 − 89.3. Power BI measure `Gap to the price leader (index points)` = 12.1 |
| 101.4 | Average supermarket's price index | `q12.txt`, first table, row Supermarket (679 shops) |
| 89.3 | Tesco's average price index | `q11.txt`, row TESCO (15 shops) |
| 15 | Tesco shops | `q11.txt`, row TESCO |
| 78 | Spike weeks in December 2025, the peak month | `q23.txt`, monthly table, row 2025-12. Power BI measure `Spike weeks in December 2025` = 78 |
| 74 | Of those, fresh produce | `q23.txt`, row 2025-12, column `of_which_fresh` |

## Other README numbers

The numbers in the README's findings, data and build sections.

| Number | Where in the README | Source |
|---|---|---|
| 21 million | Title and intro | 21,039,347 loaded price rows, `results/build_run/run_all_log.txt` and `docs/data_quality_report.md` |
| 31 | Business questions | `sql/04_analysis/q01` to `q31`, listed in `docs/stakeholders_and_questions.md` |
| 9.0% | Hypermarkets cheaper than sundry shops | `q30.txt`, finding 1 (computed before rounding) |
| 181 | Items sold in all five formats | `q03.txt`, first table, `items_compared` |
| 95.0, 104.3 | Hypermarket and sundry shop index, same 181 items | `q03.txt`, first table |
| 106.5, 97.7, 100.9 | Fresh-produce index of the average wet market, hypermarket, supermarket | `docs/findings.md`, finding 2 (q12c) |
| 49.5% | Wet markets in their state's dearest quarter | `docs/findings.md`, finding 2 (q19) |
| 11.7 | Largest district gap inside one state (Kuala Lumpur) | `q10.txt`, row W.P. Kuala Lumpur, `gap_points` |
| 30, 22 | Districts with one to three reporting shops; of them in Sabah or Sarawak | `docs/findings.md`, finding 3 (q05, q06) |
| 84%, 242, 288 | Items that moved less than 5%, of all items tracked | `docs/findings.md`, finding 4 (q13) |
| 5% | Threshold for "moved" | `docs/findings.md`, finding 4 |
| −2.4%, −5.0% | Festive staples before Chinese New Year and Hari Raya Aidilfitri | `q21.txt`: −2.42 and −4.98 |
| 16 | States | `dashboard/data/state_basket.csv` (16 rows) |
| 545 MB, 15 files | Raw data size and file count | Combined size of the 15 source files; `data/download.ps1` lists them |
| 2010 = 100 | CPI base year | DOSM CPI; `docs/data_dictionary.md`, `ref.cpi_state` |
| 21,039,347 | Price rows in staging | `run_all_log.txt`, `docs/data_quality_report.md` line 5 |
| 20,722,545 | Rows in `core.fact_price` | `run_all_log.txt` (`INSERT 0 20722545`), `docs/data_quality_report.md` |
| 6 views and 1 materialized view | Mart objects | `sql/05_views/01_create_views.sql` |
| 76; 313,598; 13; 0; 3,115 | Rows removed by each quality check | `docs/data_quality_report.md` lines 14-18; `results/build_run/04_quality_checks.txt` |
| RM 0.10; 5x and 1/5 | Thresholds of the price and outlier checks | `docs/data_quality_report.md`, lines 14 and 18 |
| 316,802 (1.51%) | Rows removed in total | `run_all_log.txt` (316802, 1.51), `docs/data_quality_report.md` line 5 |
| 15 and 3 times | Reports per item per month, wet market vs sundry shop | `docs/data_quality_report.md`, line 80 |
| 123 of 329 | Items with a different raw-row median | `docs/data_quality_report.md`, line 80 |
| 234 | Premises that joined late or stopped early | `docs/data_dictionary.md`, line 311 |
| 82 of 288; 2 points | Items misstated by the naive method | `docs/findings.md`, finding 4 (q13) |
| 42.3%; over 90% | Monday share of rows; for mini markets and sundry shops | `results/build_run/03_profile.txt` (Mon 42.3); `docs/data_quality_report.md` line 81 (95.9% and 92.3%) |
| 2.97 s → 0.09 s | Index timing test | `run_all_log.txt`, Execution Time 2967.923 ms (line 268) and 90.348 ms (line 385) |
| 43 ms → 5 ms | One item in one month | `run_all_log.txt`, Execution Time 43.102 ms (line 354) and 5.163 ms (line 435) |
| 52.5 s → 0.05 s | Normal view vs materialized view | `results/build_run/11_mv_timing.txt`: 52546.007 ms (line 10) and 46.445 ms (line 16) |
| 100 | Index base (national median) | Definition used in every index query (q03, q09, q11, q12) |
| 10,000 | "Shops per 10,000 residents" | A unit in a next-step idea, not a result |
| about 15 minutes | Build time of `sql/run_all.sql` | `sql/run_all.sql` header (line 2) |
| two weeks (14 days) | Festive window | `docs/findings.md`, finding 5; `sql/04_analysis/q21_festive_price_effect.sql` header |

## Shop-type index values in the dashboards

Index values shown in both dashboards. `dashboard/build_data.py` checks them against the build output.

| Number | What it is | Source |
|---|---|---|
| 98.4, 101.4, 103.4, 106.8, 108.2 | Average shop's price index: hypermarket, supermarket, mini market, sundry shop, wet market | `q12.txt`, first table; also the mean of `price_index` by `premise_type` in `dashboard/data/premise_index.csv` |
| 105.8, 96.3 | Basket index, Kuala Lumpur and Kedah | `q09.txt`, `state_basket.csv` |
| −2.42, −4.98 | Festive staples, all states, weighted by matched pairs | `q21.txt`; also the weighted mean of `dashboard/data/festive_effect.csv` |
