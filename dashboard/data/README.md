# Dashboard data

These 8 CSV files feed the web dashboard. They come from the `mart` views of the build run, exported by [`sql/05_views/03_export_dashboard_data.sql`](../../sql/05_views/03_export_dashboard_data.sql); the export log is [`results/build_run/12_dashboard_export.txt`](../../results/build_run/12_dashboard_export.txt). Total size: about 4 MB. The same files load straight into Power BI or Excel (Get Data → Text/CSV).

What each file holds, one row at a time.

| File | One row is | Rows | Source |
|---|---|---:|---|
| `state_basket.csv` | a state: cost of the same 265-item basket and its index (100 = national) | 16 | `mart.v_state_basket` (logic of q09) |
| `district_basket.csv` | a district: basket index; `enough_items_to_score` = f means too few items priced to compare fairly | 166 | `mart.v_district_basket` (q10) |
| `premise_index.csv` | a shop: price index against the national median of the same items, and its price quarter within its state (1 = cheapest) | 2,087 | `mart.v_premise_index` (q11, q19) |
| `item_monthly.csv` | an item in a month: national median price, change on the previous month and since October 2025 | 3,939 | `mart.v_item_monthly` (q17, q20) |
| `festive_effect.csv` | a festival × state × item set: mean price change on matched shop-item pairs in the two weeks before the festival | 160 | `mart.v_festive_effect` (q21, q22) |
| `weekly_spikes.csv` | an item in a week: median price, 8-week rolling mean, and whether the week was a spike (`is_spike` = t) | 12,786 | `mart.mv_item_weekly_spikes` (q23) |
| `item_price_by_state_type.csv` | an item × state × shop type: shops, median, lowest and highest price, national median | 15,799 | summary of `mart.v_premise_item_price` |
| `cheapest_by_item_state.csv` | an item × state: lowest price, how many shops charge it, shops compared, one example shop | 4,488 | summary of `mart.v_premise_item_price` |

Notes:

- Prices are in RM. Snapshot files (state, district, shop and item prices) use September 2026; the monthly, weekly and festive files cover October 2025 to September 2026.
- Booleans are `t` (true) and `f` (false), as PostgreSQL writes them.
- National festive figures are the average of the state rows weighted by `matched_pairs`, which gives the q21 figures.
- Spike weeks are counted by the month of `week_start`, as in q23 (for example, 78 in December 2025).
- To rebuild `dashboard/assets/data.js` and `dashboard/assets/summary.js` (the six KPIs and the figures behind the five findings) after these files change, run `python dashboard/build_data.py` from the repo root (Python 3, standard library only); it first checks the files against `results/build_run/` and stops if a check fails.
