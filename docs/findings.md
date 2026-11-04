# Findings

Five findings from 20.7 million cleaned PriceCatcher prices (October 2025 to September 2026). Every number comes from a query in `sql/04_analysis/`, and the build-run output of each query is in `results/build_run/`; the only exceptions are the policy dates in finding 5, which link to their sources. Snapshot comparisons use September 2026, and each shop counts once (`core.fact_premise_item_month`). Year-on-year and pre-festival comparisons (q13, q14, q21) use the same shop and item in both periods; monthly and weekly trend lines (q17, q18, q20, q23) use each period's median across all reporting shops.

---

## 1. Shop format matters more than most shoppers think: hypermarkets are 9% cheaper than sundry shops on the same items

- On the 181 items sold in all five formats, the price index runs from 95.0 at hypermarkets to 104.3 at sundry shops (100 = national median). Hypermarkets were **9.0% cheaper** than sundry shops. *(q03, q30)*
- Hypermarkets were the cheapest format for **159 of 242** items compared, and sundry shops the dearest for 100. Across all 242, the gap between the cheapest and dearest format has a median of 10.0%. *(q04)*
- Hypermarkets priced only **20.0%** of their items above the national median; sundry shops priced 67.9% above it. *(q07)*
- Among chains with 5+ branches (grouped by the first word of the shop name), the cheapest were Tesco and Lotus's (**89.3–89.4**), Econsave (90.2, 58 branches), Target (91.3) and Econo (91.4). The two largest networks sat further down: Mydin **95.0** (30 branches) and 99 Speedmart **95.3** (121). *(q11)*
- Price leadership is concentrated: of the "cheapest in the district on most days" titles in September, supermarkets held **59.3%** with 31.7% of the shops and hypermarkets 20.1% with 7.0%. Wet markets held 4.2% with 14.3% of the shops. *(q16)*

**What it means.** For a shopper the format choice is worth about as much as the state they live in (finding 3). For a chain, the competitive set is the hypermarkets and the discount chains, not the corner shop.

**Who should act.** Retail category manager (B): benchmark against Lotus's/Tesco and Econsave on the items in q04 with the widest format gaps (imported cabbage, cucumber, carrots, ginger, onions), where a price move is most visible to shoppers.

---

## 2. Wet markets are not the cheap place for fresh produce

- On fresh produce, shops' prices average **97.7 at hypermarkets, 100.9 at supermarkets and 106.5 at wet markets** (100 = national median). Only mini markets (109.4) and sundry shops (113.0) are dearer. *(q12c)*
- Half of all wet markets (**49.5%**) sit in their state's dearest quarter of shops, against 8.7% of hypermarkets. *(q19)*
- Example, September 2026 median per kg: standard chicken RM 8.99 at hypermarkets vs RM 10.50 at wet markets; imported garlic RM 6.99 vs RM 10.00. *(q03)*
- State by state, a hypermarket or supermarket beat the wet market on fresh produce in **14 of 16 states**. The exceptions: Sabah (wet market 103.5 vs hypermarket 104.7) and Kuala Lumpur, where wet markets (100.5) tie with hypermarkets (100.8) and are far below supermarkets (115.8). *(q12d)*
- Wet markets also re-price most often: **20.2%** of their reports show a new price, against 9.8% for sundry shops. *(q24)*

**What it means.** The common belief that the pasar is cheapest for fresh food does not hold in this data. PriceCatcher records the same item specification everywhere, but not freshness or the ability to bargain, which wet-market shoppers may value.

**Who should act.** KPDN (A): consumer price-comparison messaging can name the format gap directly. Retailer (B): fresh produce is a category where large formats already win on price and can say so.

---

## 3. The same basket costs up to 9.9% more depending on the state, and districts inside a state differ by as much

- A 265-item basket (every item priced in at least 13 of 16 states) cost **RM 4,349.65 in Kuala Lumpur and RM 3,959.53 in Kedah: 9.9% more**. *(q09, q30)*
- The five dearest are the federal territories and East Malaysia: Kuala Lumpur, Sarawak, Putrajaya, Labuan, Sabah. The cheapest are Kedah, Perak and Perlis. *(q09)*
- Inside Kuala Lumpur, district basket indexes run from **100.4 (Bandar Tun Razak) to 112.0 (Segambut)**, a gap of 11.7 points. In Sarawak the gap is 11.1 points. Malaysia's cheapest district is Bagan Datuk, Perak (91.4); the dearest is Limbang, Sarawak (113.9). *(q10)*
- 30 districts had three or fewer reporting shops in September 2026, and **22 of them are in Sabah or Sarawak**, two of the five dearest states. Both states have many premises overall (243 and 221 over the year), but spread over many districts. *(q05, q06)*

**What it means.** Location matters, but a statewide average hides as much variation as it shows. In Sabah and Sarawak, high prices meet the thinnest district-level evidence.

**Who should act.** KPDN (A): add reporting premises in the thin Sabah and Sarawak districts first, and target enforcement at district level, not state level.

---

## 4. The year's price increases were narrow, and driven by a few fresh-food categories

- Of 288 items tracked in the same shops from October 2025 to September 2026, **242 (84%) moved by less than 5%**; 38 rose by more than 5% and 8 fell by more than 5%. The median item changed by 0.0%. *(q13)*
- Three categories, **vegetables, onions/garlic/shallots and meat, made up 58% of all increases with 17% of the items**. *(q14, q30)*
- The biggest riser was tomatoes (**+69.4%**, with 95% of 1,518 shops raising the price). Cauliflower fell 27.3% and seedless watermelon 33.2%. *(q13)*
- Price-controlled staples did not move at all: coarse sugar stayed at RM 2.85 and subsidised packet cooking oil at RM 2.50 in every month. Grade B eggs fell 24.5% by April, then rose to end the year 10.1% up. *(q17, q20)*
- The method matters: comparing all shops in October with all shops in September, instead of the same shops, misstated the change by more than 2 percentage points for **82 of 288 items**. *(q13)*
- Sense check against official statistics: PriceCatcher's food prices moved with DOSM's CPI food index by state (correlation 0.60 over 160 state-months). *(q27)*

**What it means.** For most of the basket, prices were flat. The price risk is concentrated in a few fresh categories with large seasonal swings, not spread across the basket.

**Who should act.** Procurement analyst (C): use fixed-price contracts for packaged goods, and flexible or indexed contracts plus a second source for vegetables, onions and meat.

---

## 5. There was no festive price hike in 2026: staples got cheaper before Chinese New Year and Hari Raya. The spikes came in December

- Comparing the 14 days before each festival with the 4 weeks before that, in the same shops: most shop prices did not change at all (the median change is 0 for every festival). Among those that did, the average festive staple (chicken, meat, eggs, coconut, onions, fresh chillies) **fell 2.4% before Chinese New Year, 2.6% before the start of Ramadan and 5.0% before Hari Raya Aidilfitri**. All other items fell less (1.2%, 1.2%, 0.5%). Chinese New Year and Ramadan began two days apart, so those two windows nearly coincide and are best read as one result. Before Hari Raya, 47.8% of staple prices fell and 15.5% rose. *(q21)*
- Weekly price spikes (more than 2 standard deviations and 2% above the previous 8 weeks) were less common in pre-festival weeks (2.83%) than in other weeks (4.52%). *(q23)*
- December 2025 had more spike weeks than any other month (78, 74 of them fresh produce), with month-on-month jumps for red chilli (cili akar merah, +65.7%), pak choy (+50.0%) and kangkung (+39.8%). The single largest monthly jump of the year was seedless watermelon, +85.4% in June 2026. *(q17, q23)*
- Context: KPDN's festive maximum price scheme (SHMMP) capped prices of selected festive items from 13 to 21 February 2026 for Chinese New Year ([NST](https://www.nst.com.my/amp/news/nation/2026/02/1375358/nine-day-price-control-scheme-cny-starting-feb-13)) and of 27 item types from 14 to 28 March 2026 for Hari Raya Aidilfitri ([RinggitPlus](https://ringgitplus.com/ms/blog/hari-raya-aidilfitri/ini-senarai-27-jenis-barangan-harga-terkawal-sempena-hari-raya-aidilfitri-bermula-14-mac.html)). The falls are consistent with the scheme and with vegetable supply recovering after the north-east monsoon season (roughly November to March); this data has no supply or weather variable, so it cannot separate the two or prove either.

**What it means.** The festive window, which draws the attention and the enforcement, was one of the calmer parts of the year in 2026. The month with the most price spikes was December.

**Who should act.** KPDN (A): watch fresh vegetables closely in December as well as in the festive windows. Procurement (C): secure fresh-produce volumes and prices before December.

---

## Caveat

data.gov.my states that PriceCatcher is built for price surveillance, not to measure inflation; DOSM's Consumer Price Index is the official inflation measure. q27 uses CPI only to check that the two move together. PriceCatcher weights every item and shop equally, while the CPI weights by household spending, so the two are not expected to match month by month.
