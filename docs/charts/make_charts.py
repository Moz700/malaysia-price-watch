"""
Malaysia Price Watch - charts for docs/findings.md

Reads straight from the pricewatch database (via psql) and writes five PNGs
next to this file. Run after sql/run_all.sql:

    python docs/charts/make_charts.py

Needs: Python 3 with matplotlib, and psql on PATH (or set PSQL below).
On Windows set PSQL to the full path, e.g.
    PSQL = [r"C:\\Program Files\\PostgreSQL\\17\\bin\\psql.exe", "-U", "postgres"]
"""
import csv
import io
import os
import subprocess

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

PSQL = os.environ.get("PSQL_CMD", "psql").split("|")
DB = "pricewatch"
OUT = os.path.dirname(os.path.abspath(__file__))

# Palette (validated: 2 categorical slots pass CVD and contrast checks on #fcfcfb)
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK2 = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
BASE = "#c3c2b7"
S1 = "#2a78d6"   # blue
S2 = "#eb6834"   # orange

plt.rcParams.update({
    "font.family": "DejaVu Sans",
    "font.size": 10,
    "axes.edgecolor": BASE,
    "axes.labelcolor": INK2,
    "xtick.color": MUTED,
    "ytick.color": INK2,
    "figure.facecolor": SURFACE,
    "axes.facecolor": SURFACE,
})


def query(sql):
    """Run SQL with psql and return a list of dicts."""
    out = subprocess.run(PSQL + ["-d", DB, "-X", "-A", "-F", ",", "--csv", "-c", sql],
                         capture_output=True, text=True, check=True).stdout
    return list(csv.DictReader(io.StringIO(out)))


def style(ax, title, subtitle):
    ax.set_title(title, loc="left", fontsize=12.5, color=INK, fontweight="bold", pad=24)
    ax.text(0, 1.02, subtitle, transform=ax.transAxes, fontsize=9.5, color=INK2, va="bottom")
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.tick_params(length=0)


def save(fig, name):
    fig.tight_layout()
    fig.savefig(os.path.join(OUT, name), dpi=160, facecolor=SURFACE)
    plt.close(fig)
    print("wrote", name)


def hbar(ax, labels, values, color, fmt, ref=None, xlabel=""):
    y = range(len(labels))
    ax.barh(list(y), values, height=0.55, color=color, zorder=2)
    ax.set_yticks(list(y))
    ax.set_yticklabels(labels)
    ax.invert_yaxis()
    ax.xaxis.grid(True, color=GRID, linewidth=1, zorder=0)
    ax.set_axisbelow(True)
    lo = min(values + ([ref] if ref else []))
    hi = max(values)
    pad = (hi - lo) * 0.12 if hi > lo else 1
    for yi, v in zip(y, values):
        ax.text(v + pad * 0.08, yi, fmt(v), va="center", fontsize=9.5, color=INK)
    if ref is not None:
        ax.axvline(ref, color=INK2, linewidth=1, zorder=3)
    ax.set_xlabel(xlabel)
    return lo, hi, pad


def dbar(ax, labels, values, ref, color, xlabel):
    """Bars drawn from the reference value (e.g. index 100), so length = gap."""
    y = list(range(len(labels)))
    dev = [v - ref for v in values]
    ax.barh(y, dev, height=0.55, color=color, zorder=2)
    ax.set_yticks(y)
    ax.set_yticklabels(labels)
    ax.invert_yaxis()
    ax.axvline(0, color=INK2, linewidth=1, zorder=3)
    ax.xaxis.grid(True, color=GRID, linewidth=1, zorder=0)
    ax.set_axisbelow(True)
    span = max(abs(d) for d in dev)
    for yi, v, d in zip(y, values, dev):
        ax.text(d + (span * 0.03 if d >= 0 else -span * 0.03), yi, f"{v:.1f}",
                va="center", ha="left" if d >= 0 else "right", fontsize=9.5, color=INK)
    ax.set_xlim(-span * 1.35, span * 1.35)
    ax.set_xlabel(xlabel)


# ---------------------------------------------------------------------------
# 1. Shop type price index on the same items (q03)
rows = query("""
WITH sep AS (
  SELECT m.item_code, m.price, p.premise_type_en
  FROM core.fact_premise_item_month m JOIN core.dim_premise p ON p.premise_code = m.premise_code
  WHERE m.month = DATE '2026-09-01'),
common AS (SELECT item_code FROM sep GROUP BY item_code HAVING COUNT(DISTINCT premise_type_en) = 5),
it AS (SELECT item_code, premise_type_en, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) tm
       FROM sep WHERE item_code IN (SELECT item_code FROM common) GROUP BY 1, 2),
nat AS (SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) nm
        FROM sep WHERE item_code IN (SELECT item_code FROM common) GROUP BY 1)
SELECT premise_type_en AS t, ROUND((AVG(tm / nm) * 100)::numeric, 1) AS idx, COUNT(*) AS n
FROM it JOIN nat USING (item_code) GROUP BY 1 ORDER BY 2;
""")
fig, ax = plt.subplots(figsize=(7.4, 3.5))
dbar(ax, [r["t"] for r in rows], [float(r["idx"]) for r in rows], 100, S1,
     "Price index minus 100 (0 = national median)")
style(ax, "Hypermarkets are the cheapest format on the same items",
      f"Price index by shop type, {rows[0]['n']} items sold in all five types, Sep 2026")
save(fig, "chart1_shop_type_index.png")

# ---------------------------------------------------------------------------
# 2. Fresh produce index by shop type (q12c)
rows = query("""
WITH sep AS (SELECT premise_code, item_code, price FROM core.fact_premise_item_month WHERE month = DATE '2026-09-01'),
nat AS (SELECT item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) nm FROM sep GROUP BY 1),
r AS (SELECT s.premise_code, s.item_code, s.price / n.nm AS ratio FROM sep s JOIN nat n USING (item_code)
      WHERE s.premise_code IN (SELECT premise_code FROM sep GROUP BY 1 HAVING COUNT(*) >= 30))
SELECT p.premise_type_en AS t, ROUND((AVG(r.ratio) * 100)::numeric, 1) AS idx
FROM r JOIN core.dim_premise p USING (premise_code) JOIN core.dim_item i USING (item_code)
WHERE i.item_group_en = 'Fresh produce'
GROUP BY 1 ORDER BY 2;
""")
fig, ax = plt.subplots(figsize=(7.4, 3.5))
dbar(ax, [r["t"] for r in rows], [float(r["idx"]) for r in rows], 100, S1,
     "Price index minus 100 (0 = national median)")
style(ax, "Wet markets are not the cheap place for fresh produce",
      "Fresh produce price index by shop type (shops pricing 30+ items), Sep 2026")
save(fig, "chart2_fresh_produce_by_type.png")

# ---------------------------------------------------------------------------
# 3. State basket cost (q09 / mart.v_state_basket)
rows = query("SELECT state, basket_cost_rm, basket_items, items_filled_with_national "
             "FROM mart.v_state_basket ORDER BY basket_cost_rm DESC;")
labels = [r["state"] + (" *" if int(r["items_filled_with_national"]) >= 10 else "") for r in rows]
vals = [float(r["basket_cost_rm"]) for r in rows]
cheapest = min(vals)
gap = [(v / cheapest - 1) * 100 for v in vals]
fig, ax = plt.subplots(figsize=(7.4, 5.6))
y = list(range(len(labels)))
ax.barh(y, gap, height=0.55, color=S1, zorder=2)
ax.set_yticks(y)
ax.set_yticklabels(labels)
ax.invert_yaxis()
ax.axvline(0, color=INK2, linewidth=1, zorder=3)
ax.xaxis.grid(True, color=GRID, linewidth=1, zorder=0)
ax.set_axisbelow(True)
for yi, g, v in zip(y, gap, vals):
    txt = f"RM {v:,.0f}  (cheapest)" if g == 0 else f"+{g:.1f}%   RM {v:,.0f}"
    ax.text(g + 0.15, yi, txt, va="center", fontsize=9, color=INK)
ax.set_xlim(0, max(gap) * 1.55)
ax.set_xlabel("% more than the cheapest state")
style(ax, "The same basket costs up to 10% more by state",
      f"{rows[0]['basket_items']} items priced in 13+ states, sum of state medians, Sep 2026")
ax.text(0, -0.13, "* 10 or more basket items not priced in the state; national median used for those",
        transform=ax.transAxes, fontsize=8.5, color=MUTED)
save(fig, "chart3_state_basket.png")

# ---------------------------------------------------------------------------
# 4. Concentration of increases (q14)
EN = {"SAYUR-SAYURAN": "Vegetables", "BAWANG": "Onions, garlic, shallots", "DAGING": "Meat",
      "BUAH-BUAHAN": "Fruit", "AYAM": "Chicken", "BAHAN LAUT": "Seafood", "TELUR": "Eggs",
      "CILI KERING": "Dried chillies", "MINYAK DAN LEMAK": "Cooking oils and fats"}
rows = query("""
WITH o AS (SELECT premise_code, item_code, price p FROM core.fact_premise_item_month WHERE month = DATE '2025-10-01'),
s AS (SELECT premise_code, item_code, price p FROM core.fact_premise_item_month WHERE month = DATE '2026-09-01'),
c AS (SELECT o.item_code, PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.p / o.p - 1) chg
      FROM o JOIN s USING (premise_code, item_code) GROUP BY 1 HAVING COUNT(*) >= 30),
cat AS (SELECT i.item_category, COUNT(*) items, SUM(GREATEST(chg, 0)) ups
        FROM c JOIN core.dim_item i USING (item_code) GROUP BY 1)
SELECT item_category,
       ROUND((100 * ups / SUM(ups) OVER ())::numeric, 1)            AS share_up,
       ROUND((100.0 * items / SUM(items) OVER ())::numeric, 1)      AS share_items
FROM cat ORDER BY ups DESC LIMIT 7;
""")
labels = [EN.get(r["item_category"], r["item_category"].title()) for r in rows]
up = [float(r["share_up"]) for r in rows]
it = [float(r["share_items"]) for r in rows]
fig, ax = plt.subplots(figsize=(7.4, 4.6))
y = list(range(len(labels)))
h = 0.36
ax.barh([v - h / 2 - 0.01 for v in y], up, height=h, color=S1, label="Share of all price increases", zorder=2)
ax.barh([v + h / 2 + 0.01 for v in y], it, height=h, color=S2, label="Share of items", zorder=2)
for v, a, b in zip(y, up, it):
    ax.text(a + 0.4, v - h / 2, f"{a:.0f}%", va="center", fontsize=9, color=INK)
    ax.text(b + 0.4, v + h / 2, f"{b:.0f}%", va="center", fontsize=9, color=INK2)
ax.set_yticks(y)
ax.set_yticklabels(labels)
ax.invert_yaxis()
ax.xaxis.grid(True, color=GRID, linewidth=1, zorder=0)
ax.set_axisbelow(True)
ax.set_xlabel("% of total")
ax.legend(frameon=False, loc="lower right", fontsize=9)
style(ax, "A few fresh-food categories drove the year's increases",
      "Same shops, Oct 2025 vs Sep 2026, top 7 categories")
save(fig, "chart4_increase_concentration.png")

# ---------------------------------------------------------------------------
# 5. Festive effect: staples vs control (q21 / mart.v_festive_effect)
rows = query("""
SELECT festival, festival_date, item_set,
       ROUND((SUM(mean_change_pct * matched_pairs) / SUM(matched_pairs))::numeric, 2) AS chg
FROM mart.v_festive_effect
GROUP BY festival, festival_date, item_set
ORDER BY festival_date, item_set;
""")
fest = []
for r in rows:
    if r["festival"] not in fest:
        fest.append(r["festival"])
stap = [float(next(r["chg"] for r in rows if r["festival"] == f and r["item_set"] == "Festive staples")) for f in fest]
ctrl = [float(next(r["chg"] for r in rows if r["festival"] == f and r["item_set"] != "Festive staples")) for f in fest]
fig, ax = plt.subplots(figsize=(7.6, 4.2))
x = list(range(len(fest)))
w = 0.34
ax.bar([v - w / 2 - 0.01 for v in x], stap, width=w, color=S1, label="Festive staples", zorder=2)
ax.bar([v + w / 2 + 0.01 for v in x], ctrl, width=w, color=S2, label="All other items", zorder=2)
for v, a, b in zip(x, stap, ctrl):
    ax.text(v - w / 2, a + (0.15 if a >= 0 else -0.15), f"{a:+.1f}%", ha="center",
            va="bottom" if a >= 0 else "top", fontsize=9, color=INK)
    ax.text(v + w / 2, b + (0.15 if b >= 0 else -0.15), f"{b:+.1f}%", ha="center",
            va="bottom" if b >= 0 else "top", fontsize=9, color=INK2)
ax.axhline(0, color=INK2, linewidth=1, zorder=3)
ax.set_xticks(x)
ax.set_xticklabels(["Deepavali*" if f == "Deepavali" else f for f in fest], fontsize=9)
ax.yaxis.grid(True, color=GRID, linewidth=1, zorder=0)
ax.set_axisbelow(True)
ax.set_ylabel("Mean price change, %")
lo = min(stap + ctrl)
ax.set_ylim(lo - 1.2, max(stap + ctrl) + 1.2)
ax.spines["bottom"].set_visible(False)
ax.legend(frameon=False, loc="lower left", fontsize=9)
style(ax, "No festive price hike: staples got cheaper before CNY and Hari Raya",
      "Same shops, average change: 14 days before each festival vs the 4 weeks before that")
ax.text(0, -0.16, "* Deepavali baseline is only 1-5 Oct 2025 (data starts 1 Oct)",
        transform=ax.transAxes, fontsize=8.5, color=MUTED)
save(fig, "chart5_festive_effect.png")
