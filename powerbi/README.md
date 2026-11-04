# Power BI report

The Malaysia Price Watch report as a Power BI Project (PBIP): the semantic model in TMDL and the report in PBIR, stored as text so every change is reviewable in Git. It uses the same 8 CSV files as the web dashboard ([`dashboard/data/`](../dashboard/data/README.md)).

## Open it

1. Open `MalaysiaPriceWatch.pbip` in Power BI Desktop (current release).
2. If asked how to connect to web content, choose **Anonymous**.
3. Choose **Home > Refresh**.

The data loads from this repository on GitHub through one parameter, `DataSource`, so the report refreshes on any machine and in the Power BI service without a gateway. To work offline, set `DataSource` to a local folder that holds the 8 CSV files (**Home > Transform data > Edit parameters**).

## Model

A star schema: eight fact tables (one per CSV) and four dimensions.

| Table | Kind | Source file | One row is |
|---|---|---|---|
| State | dimension | state_basket.csv | a state |
| Item | dimension | item_monthly.csv | an item code, with name, unit, group, category and a unique label |
| Shop type | dimension | fixed list | a shop type, in price order |
| Month | dimension | built in Power Query | a month, October 2025 to September 2026 |
| State basket | fact | state_basket.csv | a state |
| District basket | fact | district_basket.csv | a district |
| Shop index | fact | premise_index.csv | a shop |
| Item monthly | fact | item_monthly.csv | an item in a month |
| Festive effect | fact | festive_effect.csv | a festival, state and item set |
| Weekly spikes | fact | weekly_spikes.csv | an item in a week |
| Item price by state and shop type | fact | item_price_by_state_type.csv | an item, state and shop type |
| Cheapest by item and state | fact | cheapest_by_item_state.csv | an item and state |

- Every relationship is one-to-many and filters in one direction, from the dimension to the fact. Key columns on the fact tables are hidden.
- One shared Power Query function, `fnLoadCsv`, loads each CSV, promotes the headers, sets every column type with culture en-US and turns `t`/`f` into true/false.
- Weekly spikes get a hidden "Month of week start" column, so spike weeks are counted by the month of `week_start`, as in q23.

## Measures

All measures sit in the `_Measures` table, grouped into 5 display folders; each measure has a one-line description and, where numeric, a format string.

| Folder | What the measures do |
|---|---|
| KPI | The 6 headline numbers, as fixed values. Each description names its source file in `results/build_run/`. |
| Households and policy | State and district basket cost and index, and the festive price change weighted by matched pairs (as in q21). |
| Retail pricing | Average shop's price index by shop type (as in q12), quarter shares, and item prices by shop type and state. |
| Cost risk | Monthly and weekly median prices, change since October 2025, and spike weeks. |
| Helpers | Hidden measures: colours for the district bars and the weekly spike markers, the title text of visuals that follow a slicer, and the ranks that keep each top-10 visual at exactly 10 rows. |

Medians in the CSV files are pre-computed, so the median measures return blank when a visual would add or average them across items, states, shop types, months or weeks.

## Pages

The 4 pages (1280 x 720) mirror the web dashboard.

| Page | What it shows |
|---|---|
| Overview | The 6 KPI cards, one line per stakeholder, and a data note. |
| Households and policy | State basket index (all 16 states), district basket index for the chosen state, and the festive effect. |
| Retail pricing | Average shop's price index by shop type, cheapest and dearest quarter shares, the 10 cheapest and 10 dearest shops, the item explorer (median price by shop type against the national median) and the lowest price in each state with one example shop. |
| Cost risk | Monthly median price of the chosen item, weekly median price with spike weeks in red, the top 10 risers and fallers since October 2025, and spike weeks per month. |

- The State slicer is synced between Households and policy and Retail pricing. With no state picked, charts show all states; the district chart and the item explorer then use W.P. Kuala Lumpur.
- The Item slicer is synced between Retail pricing and Cost risk and starts on AYAM BERSIH - STANDARD (1kg).
- Item names stay as KPDN publishes them (Malay).
- Each top-10 visual (cheapest and dearest shops, risers and fallers) shows exactly 10 rows. A hidden rank measure is used as a visual filter (rank 10 or less), and ties go to the lower shop code or item code.
- Visuals that follow the Item, Item group or State slicer take their title from a measure, so the title states the finding for the current choice, for example the chosen item's change since October 2025 or the dearest shop in the chosen state.
