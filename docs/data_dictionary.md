# Data dictionary

Malaysia Price Watch runs on one PostgreSQL 16 database, `pricewatch`, with four schemas used in order: `staging` (raw CSVs, never edited), `ref` (outside reference data), `core` (cleaned star schema) and `mart` (reporting views). Every count below comes from the query outputs in `results/` or from a read-only query on the built database.

## 1. Sources

The files behind the project, who publishes them and where each one lands.

| File | Publisher, site | Rows | Loaded into |
|---|---|---:|---|
| `pricecatcher_YYYY-MM.csv` (12 monthly files) | PriceCatcher (KPDN), data.gov.my | 21,039,347 | `staging.raw_price` |
| `lookup_item.csv` | PriceCatcher (KPDN), data.gov.my | 797 | `staging.lookup_item` |
| `lookup_premise.csv` | PriceCatcher (KPDN), data.gov.my | 3,929 | `staging.lookup_premise` |
| `cpi_2d_state.csv` (CPI by state) | DOSM, open.dosm.gov.my | 44,800 | `ref.cpi_state` |
| MCOICOP lookup | DOSM, open.dosm.gov.my | not loaded | names of CPI divisions 01 to 13 |

- Every file is licensed CC BY 4.0; credit data.gov.my and DOSM when reusing them.
- The study window is 1 Oct 2025 to 30 Sep 2026, 365 days. Prices exist on 346 of them.
- PriceCatcher is a price surveillance dataset. data.gov.my points to DOSM's CPI for measuring inflation, so the project uses CPI only as a sense check (q27).

## 2. Tables

### staging.raw_price

Grain: one published price (one item at one premise on one day). Rows: 21,039,347. No column has nulls, no price is zero or negative, and no (date, premise, item) key appears twice. The four columns exactly as they arrive in the monthly CSVs:

| Column | Type | Meaning | Example |
|---|---|---|---|
| `date` | DATE | Day the price was collected | 2025-10-01 |
| `premise_code` | INTEGER | Shop or market; matches `lookup_premise` | 2 |
| `item_code` | INTEGER | Item; matches `lookup_item` | 1 |
| `price` | NUMERIC(10,2) | Price in RM for the item's unit | 10.60 |

### staging.lookup_item

Grain: one item code. Rows: 797 (796 items plus the `-1` placeholder). The item lookup as published, in Malay:

| Column | Type | Meaning | Example |
|---|---|---|---|
| `item_code` | INTEGER | Item ID | 95 |
| `item` | TEXT | Item name | HALIA BASAH (TUA) |
| `unit` | TEXT | Pack size or unit the price is for | 1kg |
| `item_group` | TEXT | One of 8 broad groups (section 3) | BARANGAN SEGAR |
| `item_category` | TEXT | Finer category inside the group | SAYUR-SAYURAN |

### staging.lookup_premise

Grain: one premise code. Rows: 3,929 (3,928 premises plus the `-1` placeholder). The premise lookup as published; text may carry stray spaces:

| Column | Type | Meaning | Example |
|---|---|---|---|
| `premise_code` | INTEGER | Premise ID | 5274 |
| `premise` | TEXT | Shop or market name | MYDIN USJ |
| `address` | TEXT | Street address | LOT 4,5,6,PERSIARAN PERPADUAN USJ 1,47600 SUBANG JAYA, SELANGOR |
| `premise_type` | TEXT | Outlet type, as written (section 3) | Hypermarket |
| `state` | TEXT | State or federal territory | Selangor |
| `district` | TEXT | District | Petaling |

`staging.price_step1` (20,725,660 rows) and `staging.item_month_median` (3,939 rows) are intermediate working tables that `sql/03_model/04_fact_price.sql` builds; they are not meant for analysis.

### ref.cpi_state

Grain: one index value per state, month and CPI division. Rows: 44,800 = 16 states x 14 divisions x 200 months (Jan 2010 to Aug 2026). Base 2010 = 100 (the 2010 average of `overall` is 100.0). The DOSM file as published:

| Column | Type | Meaning | Example |
|---|---|---|---|
| `state` | TEXT | State, same spelling as `lookup_premise` | Selangor |
| `date` | DATE | First day of the month | 2026-08-01 |
| `division` | TEXT | CPI division `01` to `13`, or `overall`; `01` is food (used in q27) | 01 |
| `index` | NUMERIC(6,1) | Price index, 2010 = 100 | 175.8 |

### core.dim_item

Grain: one item. Rows: 796. Built by `sql/03_model/01_dim_item.sql`: drops the `-1` placeholder, trims every text column and adds an English group label. 338 of the 796 items have prices in `core.fact_price`. Item attributes used to filter and group prices:

| Column | Type | Meaning | Example |
|---|---|---|---|
| `item_code` | INTEGER, PK | Item ID | 95 |
| `item` | TEXT, not null | Item name (Malay) | HALIA BASAH (TUA) |
| `unit` | TEXT | Unit or pack size; 155 distinct values, `1kg` the most common (194 items) | 1kg |
| `item_group` | TEXT, not null | Malay group name | BARANGAN SEGAR |
| `item_group_en` | TEXT, not null | English group label | Fresh produce |
| `item_category` | TEXT, not null | Malay category name | SAYUR-SAYURAN |

### core.dim_premise

Grain: one premise. Rows: 3,928. Built by `sql/03_model/02_dim_premise.sql`: drops the `-1` placeholder, trims `premise_type` (merging the two wet market spellings), adds an English type label and leaves out `address`. The last four columns are filled from `core.fact_price` at the end of `04_fact_price.sql`. Premise attributes plus each premise's reporting history:

| Column | Type | Meaning | Example |
|---|---|---|---|
| `premise_code` | INTEGER, PK | Premise ID | 5274 |
| `premise` | TEXT, not null | Shop or market name | MYDIN USJ |
| `premise_type` | TEXT | Malay outlet type, trimmed | Hypermarket |
| `premise_type_en` | TEXT | English outlet type | Hypermarket |
| `state` | TEXT | State or federal territory | Selangor |
| `district` | TEXT | District | Petaling |
| `first_seen` | DATE | First day with a clean price | 2025-10-01 |
| `last_seen` | DATE | Last day with a clean price | 2026-09-29 |
| `days_reported` | INTEGER | Distinct days with a clean price | 336 |
| `reporting_pattern` | TEXT | Reporting span (values below) | Full year |

`reporting_pattern` values: Full year 2,028 premises (first price before 1 Nov 2025, last on or after 1 Sep 2026); Joined late 113; Stopped early 110; Joined late, stopped early 11; No prices in period 1,666.

### core.dim_date

Grain: one calendar day. Rows: 365 (1 Oct 2025 to 30 Sep 2026), generated with `generate_series()`. Calendar attributes for grouping by month, week, weekday and festive season:

| Column | Type | Meaning | Example |
|---|---|---|---|
| `date` | DATE, PK | Calendar day | 2026-02-10 |
| `year` | SMALLINT | Year | 2026 |
| `month` | SMALLINT | Month number | 2 |
| `month_name` | TEXT | Month name | February |
| `year_month` | TEXT | Year and month; sorts correctly as text | 2026-02 |
| `month_start` | DATE | First day of the month | 2026-02-01 |
| `iso_week` | SMALLINT | ISO week number | 7 |
| `day_of_week` | SMALLINT | 1 = Monday to 7 = Sunday | 2 |
| `day_name` | TEXT | Weekday name | Tuesday |
| `is_weekend` | BOOLEAN | Saturday or Sunday (Kedah, Kelantan and Terengganu rest on Friday and Saturday; not reflected) | false |
| `festive_period` | TEXT | `Pre-<festival>` for the 14 days before the nearest festival; NULL otherwise | Pre-Chinese New Year |

### core.dim_festival

Grain: one festival. Rows: 5. Columns: `festival` (TEXT, PK) and `festival_date` (DATE, not null). The five festivals and the `festive_period` window each one produces in `core.dim_date`; 307 days are in no window, and Pre-Ramadan has only 2 days because each day takes the nearest festival ahead and Chinese New Year falls two days before Ramadan:

| festival | festival_date | festive_period window | Days |
|---|---|---|---:|
| Deepavali | 2025-10-20 | Pre-Deepavali, 6 to 19 Oct 2025 | 14 |
| Chinese New Year | 2026-02-17 | Pre-Chinese New Year, 3 to 16 Feb 2026 | 14 |
| Ramadan | 2026-02-19 | Pre-Ramadan, 17 to 18 Feb 2026 | 2 |
| Hari Raya Aidilfitri | 2026-03-21 | Pre-Hari Raya Aidilfitri, 7 to 20 Mar 2026 | 14 |
| Hari Raya Haji | 2026-05-27 | Pre-Hari Raya Haji, 13 to 26 May 2026 | 14 |

### core.fact_price

Grain: one clean price per day, premise and item. Rows: 20,722,545 (98.494% of loaded rows), covering 338 items, 2,262 premises and 346 days. Keys: PK (`date`, `premise_code`, `item_code`); FKs to `dim_date`, `dim_premise` and `dim_item`. Built by `sql/03_model/04_fact_price.sql`, which applies the rules logged in `core.data_quality_log`. The cleaned daily price table:

| Column | Type | Meaning | Example |
|---|---|---|---|
| `date` | DATE, not null | Collection day; FK to `dim_date` | 2025-10-01 |
| `premise_code` | INTEGER, not null | FK to `dim_premise` | 5274 |
| `item_code` | INTEGER, not null | FK to `dim_item` | 95 |
| `price` | NUMERIC(10,2), not null, > 0 | Price in RM | 6.49 |

### core.fact_premise_item_month

Grain: one shop's price for one item in one month. Rows: 2,851,413. Keys: PK (`month`, `premise_code`, `item_code`); FKs to `dim_premise` and `dim_item`; index on (`item_code`, `month`). Built by `sql/03_model/06_fact_premise_item_month.sql`; `n_reports` adds back up to `fact_price` (Oct 2025: 238,303 rows from 1,797,312 daily prices). One price per shop per item per month, so every shop counts once in comparisons:

| Column | Type | Meaning | Example |
|---|---|---|---|
| `month` | DATE, not null | First day of the month | 2025-10-01 |
| `premise_code` | INTEGER, not null | FK to `dim_premise` | 5274 |
| `item_code` | INTEGER, not null | FK to `dim_item` | 95 |
| `n_reports` | BIGINT | Daily prices behind this row (1 to 31) | 30 |
| `price` | NUMERIC | Median of those prices, 2 decimals: the shop's price for the month | 6.49 |
| `avg_price` | NUMERIC | Mean of those prices, 4 decimals | 6.6900 |
| `min_price` | NUMERIC | Lowest of those prices | 6.49 |
| `max_price` | NUMERIC | Highest of those prices | 6.99 |

### core.data_quality_log

Grain: one cleaning step. Rows: 7. Columns: `step` (SMALLINT, PK), `check_name` (TEXT), `rows` (BIGINT), `action` (TEXT). The full log, where every removed row is counted under exactly one step:

| step | check_name | rows | action |
|---:|---|---:|---|
| 0 | Rows loaded into staging | 21,039,347 | start |
| 1 | Price missing or below RM 0.10 | 76 | dropped |
| 2 | Duplicate / conflicting prices (same day, shop, item) | 0 | collapsed to median |
| 4 | Item code not in lookup_item | 313,598 | dropped |
| 5 | Premise code not in lookup_premise | 13 | dropped |
| 6 | Outlier: >5x or <1/5 of item median for the month | 3,115 | dropped |
| 9 | Rows in core.fact_price | 20,722,545 | final |

### mart views

The six reporting views and the materialized view `mart.mv_item_weekly_spikes` are defined and documented in `sql/05_views/01_create_views.sql`.

## 3. Category values in the data

### Premise types

Every `premise_type` in `lookup_premise` as written (brackets show spaces), its English label and its raw price rows.

| As written | `premise_type_en` | Premises in lookup | Price rows |
|---|---|---:|---:|
| `[Pasar Raya / Supermarket]` | Supermarket | 888 | 11,326,261 |
| `[Pasar Basah ]` | Wet market | 338 | 3,689,719 |
| `[Hypermarket]` | Hypermarket | 180 | 2,677,928 |
| `[Pasar Mini]` | Mini market | 924 | 2,280,030 |
| `[Kedai Runcit]` | Sundry shop | 623 | 887,278 |
| `[Pasar Basah]` | Wet market | 22 | 177,749 |
| `[Borong]` | Wholesaler | 15 | 369 |
| `[Restoran Melayu]` | Malay restaurant | 297 | 0 |
| `[Restoran India Muslim]` | Indian Muslim restaurant | 223 | 0 |
| `[Restoran Cina]` | Chinese restaurant | 196 | 0 |
| `[Medan Selera]` | Food court (Medan Selera) | 126 | 0 |
| `[Foodcourt]` | Food court | 94 | 0 |
| `[Kedai Serbaneka]` | Convenience store | 2 | 0 |
| (blank) | placeholder `-1`, removed | 1 | 0 |

- `'Pasar Basah '` (trailing space, 338 premises) and `'Pasar Basah'` (22) are the same outlet type. Without `TRIM()` they split into two groups; `dim_premise` merges them into 360 wet markets.
- The 6 restaurant, food-court and convenience-store types hold 938 premises in the lookup and zero price rows in this period, as do the 240 cooked-food and convenience-store items below. Wholesalers have only 369 rows.

### Item groups

The 8 item groups, their English labels and how many items in each are priced.

| `item_group` | `item_group_en` | Items in lookup | Items priced | Price rows |
|---|---|---:|---:|---:|
| BARANGAN SEGAR | Fresh produce | 164 | 122 | 12,448,037 |
| BARANGAN BERBUNGKUS | Packaged goods | 219 | 109 | 3,795,472 |
| BARANGAN KERING | Dry goods | 27 | 24 | 2,369,541 |
| SUSU DAN BARANGAN BAYI | Milk and baby products | 50 | 26 | 1,047,584 |
| MINUMAN | Beverages | 50 | 31 | 540,372 |
| PRODUK KEBERSIHAN | Household and hygiene | 46 | 27 | 524,743 |
| BARANGAN KEDAI SERBANEKA | Convenience store goods | 49 | 0 | 0 |
| MAKANAN SIAP MASAK | Cooked food | 191 | 0 | 0 |
| **Total** | | **796** | **339** | **20,725,749** |

### States

Premises per state in the lookup against premises that reported at least one price (the 13 rows of premise 22280, missing from the lookup, are not in the total).

| State | Premises in lookup | Premises reporting | Price rows |
|---|---:|---:|---:|
| Johor | 390 | 224 | 2,455,833 |
| W.P. Kuala Lumpur | 373 | 191 | 2,381,145 |
| Perak | 370 | 195 | 2,096,853 |
| Sarawak | 396 | 243 | 1,975,637 |
| Pahang | 308 | 195 | 1,713,442 |
| Selangor | 248 | 139 | 1,661,760 |
| Kelantan | 378 | 216 | 1,597,165 |
| Pulau Pinang | 225 | 153 | 1,486,556 |
| Sabah | 349 | 221 | 1,302,544 |
| Kedah | 222 | 122 | 1,210,405 |
| Terengganu | 253 | 151 | 1,155,371 |
| Negeri Sembilan | 160 | 75 | 738,573 |
| Melaka | 92 | 54 | 522,747 |
| W.P. Putrajaya | 51 | 28 | 325,815 |
| Perlis | 87 | 39 | 290,754 |
| W.P. Labuan | 26 | 16 | 124,734 |
| **Total** | **3,928** | **2,262** | **21,039,334** |

### Priced item categories

The 36 categories that have prices, with an English gloss, items priced and raw price rows.

| Group | `item_category` | English | Items | Price rows |
|---|---|---|---:|---:|
| Fresh produce | SAYUR-SAYURAN | vegetables | 37 | 7,336,536 |
| Fresh produce | BAHAN LAUT | seafood | 27 | 2,521,089 |
| Fresh produce | BUAH-BUAHAN | fruit | 16 | 760,401 |
| Fresh produce | TELUR | eggs | 6 | 672,011 |
| Fresh produce | AYAM | chicken | 7 | 563,505 |
| Fresh produce | IKAN DARAT | freshwater fish | 2 | 395,093 |
| Fresh produce | DAGING | meat | 22 | 87,387 |
| Fresh produce | MEE/KUETIAU | fresh noodles | 1 | 63,898 |
| Fresh produce | KELAPA | coconut | 4 | 48,117 |
| Packaged goods | MINYAK DAN LEMAK | cooking oils and fats | 33 | 965,383 |
| Packaged goods | REMPAH RATUS (BERBUNGKUS) | spices, packaged | 14 | 759,473 |
| Packaged goods | KICAP DAN SOS | soy sauce and sauces | 6 | 426,699 |
| Packaged goods | SAPUAN (SPREADS) | spreads | 8 | 293,064 |
| Packaged goods | KRIMER DAN SUSU TEPUNG | creamer and milk powder | 5 | 231,503 |
| Packaged goods | SANTAN (KOTAK) | coconut milk, boxed | 4 | 221,158 |
| Packaged goods | IKAN DALAM TIN | canned fish | 3 | 161,346 |
| Packaged goods | GULA | sugar | 3 | 138,148 |
| Packaged goods | TEPUNG | flour | 5 | 137,971 |
| Packaged goods | BIHUN | rice vermicelli | 4 | 137,421 |
| Packaged goods | BERAS | rice | 19 | 133,012 |
| Packaged goods | MI SEGERA | instant noodles | 1 | 89,001 |
| Packaged goods | ESEN DAN RAGI | essences and raising agents | 2 | 52,279 |
| Packaged goods | MENTEGA | butter | 1 | 31,414 |
| Packaged goods | REMPAH RATUS (TIDAK BERBUNGKUS) | spices, loose | 1 | 17,600 |
| Dry goods | BAWANG | onions, garlic, shallots | 10 | 1,698,714 |
| Dry goods | UBI KENTANG | potatoes | 3 | 409,296 |
| Dry goods | KACANG | pulses and beans | 7 | 149,029 |
| Dry goods | CILI KERING | dried chillies | 2 | 86,238 |
| Dry goods | HASIL LAUT KERING | dried seafood | 2 | 26,264 |
| Milk and baby | SUSU BAYI | infant formula | 15 | 639,811 |
| Milk and baby | LAMPIN PAKAI BUANG | disposable nappies | 6 | 242,327 |
| Milk and baby | MAKANAN BAYI | baby food | 5 | 165,446 |
| Beverages | TERSEDIA MINUM | ready-to-drink | 20 | 362,141 |
| Beverages | BAHAN-BAHAN MINUMAN | drink ingredients (coffee, cordials) | 11 | 178,231 |
| Household and hygiene | PENJAGAAN DIRI | personal care | 15 | 285,767 |
| Household and hygiene | PENJAGAAN RUMAH | household care | 12 | 238,976 |

## 4. Things to know before analysing

- 19 days have no prices at all. 13 are national public holidays; the other 6 are not.
  - Public holidays: Christmas (Thu 25 Dec 2025), Chinese New Year (Tue 17, Wed 18 Feb 2026), Hari Raya Aidilfitri (Sat 21, Sun 22, Mon 23 Mar), Labour Day (Fri 1 May), Hari Raya Haji (Wed 27 May), Agong's Birthday (Mon 1 Jun), Awal Muharram (Wed 17 Jun), Maulidur Rasul (Tue 25 Aug), National Day (Mon 31 Aug), Malaysia Day (Wed 16 Sep).
  - No national holiday: Fri 13 Feb, Sat 14 Mar, Thu 19 Mar, Fri 20 Mar, Sat 20 Jun, Wed 30 Sep 2026.
  - February and March 2026 have the fewest days with data (25 each); February has the fewest rows (1,369,552).
- Collection happens mostly on Mondays. 42.3% of all rows fall on a Monday, against 8.7% to 12.3% for each other weekday. Mini markets and sundry shops report almost only on Mondays, about once a week.

Share of September 2026 rows collected on a Monday, and average reports per shop per item per month, by outlet type.

| Outlet type | Monday share, Sep 2026 | Reports per shop-item-month, Sep 2026 |
|---|---:|---:|
| Sundry shop | 95.9% | 3.3 |
| Mini market | 92.3% | 3.4 |
| Hypermarket | 44.5% | 7.6 |
| Supermarket | 42.5% | 8.1 |
| Wet market | 18.8% | 15.4 |

- A public-holiday Monday thins out the whole week. Three Mondays have no data (23 Mar, 1 Jun, 31 Aug 2026). In the week of 31 Aug only 1,138 premises reported, against 2,117 in the median week; the week of 23 Mar had 1,203. Weekly series need a minimum-premises filter (q18 uses 100 shops per item).
- Shops do not report equally often. A wet market sends about 15.4 prices per item per month, a sundry shop about 3.3. A median over `fact_price` rows lets frequent reporters outvote the rest, so `core.fact_premise_item_month` gives each shop one price per item per month. Use it for any comparison across shops, states or outlet types.
- Both lookups have a placeholder row: `lookup_item` has `item_code = -1` (all text blank) and `lookup_premise` has `premise_code = -1` ("Unknown Premise", "Unknown Address", blank type, state and district). No price row uses either code; both are dropped from the dimensions.
- 17 item codes in the prices are missing from `lookup_item`. They cover 313,598 rows (1.491%), codes between 2023 and 2096. The 12 largest were priced all year by 440 to 882 premises. With no name or unit they are dropped from `fact_price`. Premise 22280 is likewise missing from `lookup_premise` (13 rows, 25 to 26 Sep 2026).
- Prices have at most 2 decimals, so `NUMERIC(10,2)` stores them exactly. This was checked on the raw CSV text before loading (no price has a third decimal), because once loaded into `NUMERIC(10,2)` a third decimal would already be rounded away. The raw data holds 3,735 distinct price values.
- Raw prices run from RM 0.01 to RM 7,985.00. The maximum is one row for S-26 SMA infant formula 550 g (item 2062, 27 Apr 2026). Two rules handle the extremes: an absolute floor drops the 76 prices below RM 0.10, and a relative rule drops 3,115 prices above 5x (367) or below 1/5 (2,748) of the item's median for the month (the full-year median when the item has fewer than 20 reports that month). The floor exists because the relative rule alone let one RM 0.01 price through: IKAN GELAMA (item 49) was reported once all year, so that price was its own median. After both rules `fact_price` runs from RM 0.45 to RM 285.50.
- Premises join and leave. 2,028 premises report for the full year; 234 joined late or stopped early (`dim_premise.reporting_pattern`). Compare like with like when tracking a price over time.
- CPI stops at August 2026. Any join from prices to `ref.cpi_state` covers October 2025 to August 2026 only.
