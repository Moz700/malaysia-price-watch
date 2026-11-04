"""Build dashboard/assets/data.js from the 8 CSV files in dashboard/data/.

Run from the repo root (Python 3, standard library only):

    python dashboard/build_data.py

What it does:
1. Reads the 8 CSVs and turns them into compact column-oriented JSON
   (one list per column). Item names, units and groups are stored once in an
   "items" lookup instead of on every row.
2. Checks that the CSVs still reproduce the numbers printed in
   results/build_run/ (q03, q09, q11, q12, q14, q21, q23, q31). If any check
   fails, it stops and does not write data.js.
   It also stores q12's state by shop-type table as printed, because the
   CSV rounds each shop's index and its means can be 0.1 off.
3. Writes assets/data.js, which sets one global variable, MPW_DATA, and
   assets/summary.js (MPW_SUMMARY): the six KPIs and the small tables
   behind the hero and the five findings (q03, q12, q14, q19, q21, q23). The page
   loads summary.js first and data.js only when the explorer is needed. Both are
   loaded with script tags, so the page also works when opened from disk
   (file://), where fetch() is blocked.
"""

import csv
import json
import re
import sys
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA_DIR = HERE / "data"
RESULTS_DIR = HERE.parent / "results" / "build_run"
OUT_FILE = HERE / "assets" / "data.js"
SUMMARY_FILE = HERE / "assets" / "summary.js"
MAX_BYTES = 6 * 1024 * 1024

# Expected row counts, from dashboard/data/README.md.
EXPECTED_ROWS = {
    "state_basket": 16,
    "district_basket": 166,
    "premise_index": 2087,
    "item_monthly": 3939,
    "festive_effect": 160,
    "weekly_spikes": 12786,
    "item_price_by_state_type": 15799,
    "cheapest_by_item_state": 4488,
}

# Columns that hold numbers. Everything else stays text.
NUMERIC = {
    "item_code", "basket_items", "items_filled_with_national", "basket_cost_rm",
    "basket_index", "max_shops_per_item", "basket_items_priced", "premise_code",
    "items_priced", "price_index", "price_quartile_in_state", "premises",
    "median_price_rm", "mom_change_pct", "change_since_first_month_pct",
    "matched_pairs", "mean_change_pct", "pct_pairs_up", "rolling_8wk_mean_rm",
    "rolling_8wk_sd", "shops", "min_price_rm", "max_price_rm",
    "national_median_rm", "lowest_price_rm", "shops_at_lowest_price",
    "shops_compared",
}
BOOLEAN = {"enough_items_to_score", "is_spike"}
# Item description columns moved into the shared "items" lookup.
ITEM_COLUMNS = ("item", "unit", "item_group", "item_category")

errors = []


def check(ok, label):
    """Print one check result and remember failures."""
    print(("PASS " if ok else "FAIL ") + label)
    if not ok:
        errors.append(label)


def round1(value):
    """Round half up to 1 decimal, the way PostgreSQL ROUND(numeric, 1) does."""
    return Decimal(value).quantize(Decimal("0.1"), rounding=ROUND_HALF_UP)


def round2(value):
    return Decimal(value).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def read_csv(name):
    with open(DATA_DIR / f"{name}.csv", newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def convert(column, text):
    if text == "":
        return None
    if column in BOOLEAN:
        if text not in ("t", "f"):
            raise ValueError(f"{column}: expected t or f, got {text!r}")
        return text == "t"
    if column in NUMERIC:
        number = float(text)
        return int(number) if number.is_integer() and "." not in text else number
    return text


def psql_tables(name):
    """Parse the result tables in a psql output file into lists of dicts."""
    lines = (RESULTS_DIR / f"{name}.txt").read_text(encoding="utf-8").splitlines()
    tables = []
    for i in range(1, len(lines)):
        if re.fullmatch(r"-+(\+-+)+", lines[i].strip()) and "|" in lines[i - 1]:
            header = [h.strip() for h in lines[i - 1].split("|")]
            rows = []
            for line in lines[i + 1:]:
                if line.startswith("(") and "row" in line:
                    break
                rows.append(dict(zip(header, [c.strip() for c in line.split("|")])))
            tables.append(rows)
    return tables


# Read CSVs
raw = {name: read_csv(name) for name in EXPECTED_ROWS}
for name, expected in EXPECTED_ROWS.items():
    check(len(raw[name]) == expected, f"{name}.csv has {expected} rows (found {len(raw[name])})")

# One shared item lookup table
items = {}
conflicts = 0
for name, rows in raw.items():
    for row in rows:
        if "item_code" not in row:
            continue
        code = int(row["item_code"])
        entry = items.setdefault(code, {})
        for col in ITEM_COLUMNS:
            if col in row:
                if col in entry and entry[col] != row[col]:
                    conflicts += 1
                entry.setdefault(col, row[col])
check(conflicts == 0, f"item name, unit and group agree across files for all {len(items)} items")

# Verification checks
basket = {r["state"]: r for r in raw["state_basket"]}
kl = Decimal(basket["W.P. Kuala Lumpur"]["basket_cost_rm"])
kedah = Decimal(basket["Kedah"]["basket_cost_rm"])
check(kl == Decimal("4349.65") and kedah == Decimal("3959.53"),
      f"basket cost W.P. Kuala Lumpur RM {kl}, Kedah RM {kedah} (q09)")
check(round1((kl / kedah - 1) * 100) == Decimal("9.9"), "KPI 1: KL basket is 9.9% above Kedah (q09)")
check(basket["W.P. Kuala Lumpur"]["basket_index"] == "105.8" and basket["Kedah"]["basket_index"] == "96.3",
      "basket index W.P. Kuala Lumpur 105.8, Kedah 96.3 (q09)")

# q12: mean of each shop's own price index, by shop type.
q12 = {r["premise_type_en"]: r["avg_price_index"] for r in psql_tables("q12")[0]}
by_type = {}
for r in raw["premise_index"]:
    by_type.setdefault(r["premise_type"], []).append(Decimal(r["price_index"]))
for shop_type, expected in q12.items():
    values = by_type.get(shop_type, [])
    got = round1(sum(values) / len(values)) if values else None
    check(str(got) == expected, f"shop-type index {shop_type} = {got} (q12 says {expected})")

# q12 second table: average shop index by state and shop type. premise_index.csv
# rounds each shop's index to 0.1, so a mean taken from the CSV can be 0.1 off
# the printed value. The dashboard shows the printed q12 values for a state.
Q12_COLUMNS = {"Hypermarket": "hypermarket", "Supermarket": "supermarket", "Mini market": "mini_market",
               "Sundry shop": "sundry_shop", "Wet market": "wet_market"}
by_state_type = {}
for r in raw["premise_index"]:
    by_state_type.setdefault((r["state"], r["premise_type"]), []).append(Decimal(r["price_index"]))
q12_state = {}
off = []
for r in psql_tables("q12")[1]:
    q12_state[r["state"]] = {}
    for shop_type, column in Q12_COLUMNS.items():
        printed = r[column]
        values = by_state_type.get((r["state"], shop_type), [])
        q12_state[r["state"]][shop_type] = float(printed) if printed else None
        if bool(printed) != bool(values) or (values and abs(sum(values) / len(values) - Decimal(printed)) > Decimal("0.1")):
            off.append(f"{r['state']} {shop_type}")
    # the all-types column, used by the map when no shop type is chosen
    q12_state[r["state"]]["All shop types"] = float(r["all_types"])
check(sorted(q12_state) == sorted(basket) and not off,
      f"q12 state table has all {len(basket)} states; each value is within 0.1 of the CSV mean"
      + (f" (not: {', '.join(off)})" if off else ""))

# q21: national festive effect = state rows weighted by matched_pairs.
q21 = {}
for r in psql_tables("q21")[0]:
    item_set = "Festive staples" if r["item_set"] == "Festive staples" else "Other items (control)"
    q21[(r["festival"], item_set)] = (r["matched_pairs"], r["mean_change_pct"])
sums = {}
for r in raw["festive_effect"]:
    key = (r["festival"], r["item_set"])
    pairs, total = sums.get(key, (0, Decimal(0)))
    sums[key] = (pairs + int(r["matched_pairs"]), total + int(r["matched_pairs"]) * Decimal(r["mean_change_pct"]))
for key, (pairs_txt, mean_txt) in q21.items():
    pairs, total = sums[key]
    got = round2(total / pairs)
    check(str(pairs) == pairs_txt and str(got) == mean_txt,
          f"festive {key[0]} / {key[1]}: {pairs} pairs, {got}% (q21 says {pairs_txt}, {mean_txt}%)")

# q23: spike weeks by month of week_start, total and fresh produce.
q23 = {r["month"]: (r["spike_weeks"], r["of_which_fresh"]) for r in psql_tables("q23")[-1]}
spikes = {}
for r in raw["weekly_spikes"]:
    if r["is_spike"] == "t":
        month = r["week_start"][:7]
        total, fresh = spikes.get(month, (0, 0))
        spikes[month] = (total + 1, fresh + (r["item_group"] == "Fresh produce"))
check({m: (str(a), str(b)) for m, (a, b) in spikes.items()} == q23,
      f"spike weeks by month match q23 for all {len(q23)} months")
check(spikes.get("2025-12", (0,))[0] == 78, "KPI 6: 78 spike weeks in December 2025 (q23)")
check(max(spikes, key=lambda m: spikes[m][0]) == "2025-12", "December 2025 is the peak month for spikes (q23)")

# q23 tests a week only when it has 8 earlier kept weeks (weeks_in_window = 8),
# that is from the 9th row of each item in weekly_spikes.csv. The dashboard uses
# this rule; check that it gives q23's spike rate for every month.
weeks_by_item = {}
for r in raw["weekly_spikes"]:
    weeks_by_item.setdefault(r["item_code"], []).append(r["week_start"])
tested = {}
for weeks in weeks_by_item.values():
    for week in sorted(weeks)[8:]:
        tested[week[:7]] = tested.get(week[:7], 0) + 1
rates = {r["month"]: r["spike_rate_pct"] for r in psql_tables("q23")[-1]}
check(sorted(tested) == sorted(rates)
      and all(str(round2(Decimal(spikes[m][0]) * 100 / tested[m])) == rates[m] for m in rates),
      f"8-earlier-weeks rule gives q23's spike rate for all {len(rates)} months; first tested month {min(tested)}")

# KPI 2: q03 second table, one unit of each of 8 staples per shop type.
staples = psql_tables("q03")[1]
wet = sum(Decimal(r["wet_market"]) for r in staples)
hyper = sum(Decimal(r["hypermarket"]) for r in staples)
check(len(staples) == 8 and wet == Decimal("99.45") and hyper == Decimal("88.76"),
      f"KPI 2: 8 staples cost RM {wet} at wet markets, RM {hyper} at hypermarkets (q03)")
check(round1((wet / hyper - 1) * 100) == Decimal("12.0"), "KPI 2: staples gap is 12.0% (q03)")

# KPI 3: q31 first table, all controlled items together (item_code 0).
q31 = {r["item_code"]: r for r in psql_tables("q31")[0]}
check(q31["0"]["shop_months"] == "34609" and q31["0"]["pct_at_or_below"] == "99.95",
      "KPI 3: 99.95% of 34,609 shop-months at or below the controlled price (q31)")

# KPI 4: q14, the first three categories by share of increases.
q14 = psql_tables("q14")[0][:3]
top3 = [r["item_category"] for r in q14]
item_share = sum(Decimal(r["share_of_items_pct"]) for r in q14)
check(top3 == ["SAYUR-SAYURAN", "BAWANG", "DAGING"] and q14[2]["cumulative_share_pct"] == "57.6"
      and item_share == Decimal("17.0"),
      f"KPI 4: vegetables, onions and garlic, meat = {q14[2]['cumulative_share_pct']}% of increases, "
      f"{item_share}% of items (q14)")

# KPI 5: average supermarket index (q12) minus Tesco's average (q11).
tesco = [r for t in psql_tables("q11") for r in t if r.get("name_first_word") == "TESCO"]
check(len(tesco) == 1 and tesco[0]["branches"] == "15" and tesco[0]["avg_index"] == "89.3",
      "KPI 5: Tesco average index 89.3 over 15 shops (q11)")
check(Decimal(q12["Supermarket"]) - Decimal(tesco[0]["avg_index"]) == Decimal("12.1"),
      "KPI 5: 101.4 - 89.3 = 12.1 points (q11, q12)")

# Figures for the hero and the findings
# These go into assets/summary.js, a small file the page loads first.

# Finding 1: q03 first table, price index of each shop type on the same 181 items.
q03_types = {r["premise_type_en"]: r for r in psql_tables("q03")[0]}
check(len(q03_types) == 5 and all(r["items_compared"] == "181" for r in q03_types.values())
      and q03_types["Hypermarket"]["price_index"] == "95.0" and q03_types["Sundry shop"]["price_index"] == "104.3",
      "finding 1: on the same 181 items, hypermarket 95.0, sundry shop 104.3 (q03)")

# Finding 2: q12 third table, fresh-produce index by shop type (average of shops).
q12_groups = {r["item_group_en"]: r for r in psql_tables("q12")[2]}
fresh = q12_groups.get("Fresh produce", {})
check(fresh.get("hypermarket") == "97.7" and fresh.get("supermarket") == "100.9" and fresh.get("wet_market") == "106.5",
      "finding 2: fresh produce index hypermarket 97.7, supermarket 100.9, wet market 106.5 (q12)")

# Finding 2: share of each shop type's shops in the dearest quarter of their state (q19),
# from premise_index.csv price_quartile_in_state.
q19 = {r["premise_type_en"]: r for r in psql_tables("q19")[1]}
quarter = {}
for r in raw["premise_index"]:
    n, q1, q4 = quarter.get(r["premise_type"], (0, 0, 0))
    quarter[r["premise_type"]] = (n + 1, q1 + (r["price_quartile_in_state"] == "1"), q4 + (r["price_quartile_in_state"] == "4"))
quarter_pct = {t: (n, str(round1(Decimal(q1) * 100 / n)), str(round1(Decimal(q4) * 100 / n))) for t, (n, q1, q4) in quarter.items()}
check(all(quarter_pct[t] == (int(r["premises"]), r["pct_in_cheapest_q"], r["pct_in_dearest_q"]) for t, r in q19.items()),
      "finding 2: cheapest and dearest quarter shares by shop type match q19 (wet market 49.5%, hypermarket 8.7%)")

# Finding 4: q14, share of all price increases by item category, and q13 item counts.
q14_all = psql_tables("q14")[0]
check(len(q14_all) == 36 and q14_all[7]["cumulative_share_pct"] == "88.2",
      "finding 4: q14 has 36 categories; the top 8 make 88.2% of increases")

# Finding 5: national festive effect, state rows weighted by matched pairs (checked above against q21).
festive_dates = {r["festival"]: r["festival_date"] for r in raw["festive_effect"]}
festive_national = []
for festival in sorted(festive_dates, key=festive_dates.get):
    entry = {"festival": festival, "date": festive_dates[festival]}
    for item_set, key in (("Festive staples", "staples"), ("Other items (control)", "other")):
        pairs, total = sums[(festival, item_set)]
        entry[key] = {"mean": float(round2(total / pairs)), "pairs": pairs}
    festive_national.append(entry)

spikes_by_month = [{"month": m, "spike_weeks": spikes[m][0], "fresh": spikes[m][1],
                    "rate": float(rates[m])} for m in sorted(rates)]

if errors:
    print(f"\n{len(errors)} check(s) failed. data.js was not written.")
    sys.exit(1)

# KPI tiles (checked above)
kpis = [
    {"value": "9.9%", "label": "Regional basket gap",
     "meaning": "The same 265-item basket cost RM 4,349.65 in W.P. Kuala Lumpur and RM 3,959.53 in Kedah, "
                "RM 390.12 more (September 2026).",
     "source": "state_basket.csv, q09"},
    {"value": "12.0%", "label": "Staples gap, wet market vs hypermarket",
     "meaning": "One of each of 8 everyday staples cost RM 99.45 at wet markets and RM 88.76 at hypermarkets.",
     "source": "q03"},
    {"value": "99.95%", "label": "Price-control adherence",
     "meaning": "Share of 34,609 shop-months at or below the controlled price "
                "(coarse sugar RM 2.85/kg, packet cooking oil RM 2.50/kg).",
     "source": "q31"},
    {"value": "58%", "label": "Price increases from 3 categories",
     "meaning": "Vegetables, onions and garlic, and meat made up 58% of all price increases "
                "with 17% of the items.",
     "source": "q14"},
    {"value": "12.1 points", "label": "Gap to the price leader",
     "meaning": "The average supermarket's price index was 101.4; Tesco, the cheapest chain, "
                "averaged 89.3 over its 15 shops.",
     "source": "premise_index.csv, q11, q12"},
    {"value": "78", "label": "Spike weeks in December 2025",
     "meaning": "Item-weeks priced well above their recent normal in December 2025, the peak month.",
     "source": "weekly_spikes.csv, q23"},
]

# Small figures drawn next to each KPI value, all checked above.
kpis[0]["spark"] = {"kind": "states", "highlight": ["W.P. Kuala Lumpur", "Kedah"]}
kpis[1]["spark"] = {"kind": "pair", "items": [
    {"label": "Wet market", "value": float(wet), "text": f"RM {wet}"},
    {"label": "Hypermarket", "value": float(hyper), "text": f"RM {hyper}"}]}
kpis[2]["spark"] = {"kind": "meter", "value": float(q31["0"]["pct_at_or_below"]),
                    "above": int(q31["0"]["above_controlled"]), "total": int(q31["0"]["shop_months"])}
kpis[3]["spark"] = {"kind": "share", "share": float(q14[2]["cumulative_share_pct"]), "items": float(item_share)}
kpis[4]["spark"] = {"kind": "gap", "from": {"label": "Tesco", "value": float(tesco[0]["avg_index"])},
                    "to": {"label": "Average supermarket", "value": float(q12["Supermarket"])}}
kpis[5]["spark"] = {"kind": "months"}

summary = {
    "note": "Built by dashboard/build_data.py from dashboard/data/*.csv and results/build_run/. Do not edit by hand.",
    "kpis": kpis,
    "state_basket": [{"state": r["state"], "basket_cost_rm": float(r["basket_cost_rm"]),
                      "basket_index": float(r["basket_index"]), "basket_items": int(r["basket_items"]),
                      "items_filled_with_national": int(r["items_filled_with_national"])}
                     for r in raw["state_basket"]],
    "q03_type_index": [{"type": t, "index": float(r["price_index"]), "items": int(r["items_compared"]),
                        "below": int(r["items_below_national"]), "above": int(r["items_above_national"])}
                       for t, r in q03_types.items()],
    "q12_type_index": {t: float(v) for t, v in q12.items()},
    "q12_fresh_index": {t: float(fresh[c]) for t, c in Q12_COLUMNS.items()},
    "q19_quarters": {t: {"shops": n, "cheapest": float(c), "dearest": float(d)} for t, (n, c, d) in quarter_pct.items()},
    "q14_categories": [{"category": r["item_category"], "items": int(r["items"]),
                        "share": float(r["share_of_all_increases_pct"]),
                        "cumulative": float(r["cumulative_share_pct"]),
                        "share_of_items": float(r["share_of_items_pct"])} for r in q14_all],
    "festive_national": festive_national,
    "spikes_by_month": spikes_by_month,
}
summary_text = ("// Generated by dashboard/build_data.py. Do not edit by hand.\n"
                "window.MPW_SUMMARY = " + json.dumps(summary, separators=(",", ":")) + ";\n")

# Column-oriented tables
tables = {}
for name, rows in raw.items():
    columns = [c for c in rows[0].keys() if c not in ITEM_COLUMNS]
    tables[name] = {c: [convert(c, r[c]) for r in rows] for c in columns}

codes = sorted(items)
tables["items"] = {"item_code": codes}
for col in ITEM_COLUMNS:
    tables["items"][col] = [items[c].get(col) for c in codes]

payload = {
    "note": "Built by dashboard/build_data.py from dashboard/data/*.csv (q12_state_index from results/build_run/q12.txt). Do not edit by hand.",
    "kpis": kpis,
    "q12_state_index": q12_state,
    "tables": tables,
}
text = ("// Generated by dashboard/build_data.py from dashboard/data/*.csv. Do not edit by hand.\n"
        "window.MPW_DATA = " + json.dumps(payload, separators=(",", ":")) + ";\n")
size = len(text.encode("utf-8"))
check(size < MAX_BYTES, f"data.js is {size / 1024 / 1024:.2f} MB (limit 6 MB)")
if errors:
    sys.exit(1)
OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
OUT_FILE.write_text(text, encoding="utf-8")
SUMMARY_FILE.write_text(summary_text, encoding="utf-8")
print(f"\nWrote {OUT_FILE.relative_to(HERE.parent)} ({size:,} bytes) and "
      f"{SUMMARY_FILE.relative_to(HERE.parent)} ({len(summary_text.encode('utf-8')):,} bytes).")
