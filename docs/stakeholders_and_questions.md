# Stakeholders and questions

Every query in `sql/04_analysis/` answers a question one of three stakeholders would ask. The answers, with numbers, are in [`findings.md`](findings.md) and in the comment block of each query file.

## The three stakeholders

What each one is responsible for and the decision the analysis feeds.

| | Stakeholder | Cares about | Decision this project informs | Web dashboard tab |
|---|---|---|---|---|
| A | Consumer and policy analyst, KPDN (Ministry of Domestic Trade and Cost of Living) | Affordability and fairness across states and districts | Where to focus price enforcement and monitoring | 1. Households and policy |
| B | Retail category manager, supermarket chain | Price positioning against competing formats and chains | Which items and formats to price against, where to run promotions | 2. Retail pricing |
| C | Procurement / supply chain analyst, FMCG supplier | Volatility, seasonality and regional price gaps | Which items need flexible contracts or hedging, and when | 3. Cost risk |

## Questions and the query that answers each

All 31 questions, in order of SQL complexity. Snapshot questions use September 2026; change questions compare October 2025 with September 2026 on matched shops.

| # | Stakeholder | Question | SQL techniques |
|---|---|---|---|
| q01 | A | National median price of each item, Sep 2026 | JOIN, GROUP BY, PERCENTILE_CONT |
| q02 | A | Most and least expensive state for the 10 most common items | CTE, AVG, RANK |
| q03 | B | How prices differ by shop type for the same item | GROUP BY two columns, FILTER pivot |
| q04 | B | Items with the biggest gap between cheapest and dearest shop type | CTE, MAX − MIN, ARRAY_AGG |
| q05 | C | Items and premises per state: is coverage balanced? | COUNT DISTINCT, SUM() OVER () |
| q06 | A | Districts with the fewest reporting shops ("price-information deserts") | GROUP BY, HAVING, anti-join |
| q07 | B | How many items each shop type prices above the national median | CASE inside SUM, FILTER |
| q08 | C | Item categories with the widest shop-to-shop price spread | STDDEV ÷ AVG, percentiles |
| q09 | A | Cost of the same essentials basket in each state | multi-step CTE, CROSS JOIN, COALESCE |
| q10 | A | Cheapest district within each state | correlated subquery |
| q11 | B | Premise price index: the cheapest shops and chains | ratio metric, HAVING |
| q12 | B | Price index by shop type × state, and shop type × item group | CTE + GROUP BY, FILTER pivot |
| q13 | C | Items that changed price most from Oct 2025 to Sep 2026 (naive vs matched shops) | two-period CTE |
| q14 | C | Are increases concentrated in a few categories? | share of total, running share |
| q15 | B | Rank shops by price for each item within each district | ROW_NUMBER, RANK, DENSE_RANK |
| q16 | B | Which shop is cheapest most often, day after day | DENSE_RANK + COUNT, ROW_NUMBER |
| q17 | C | Month-on-month median price change per item | LAG |
| q18 | C | Rolling 4-week average for rice, chicken, eggs, cooking oil, sugar | AVG() OVER (ROWS BETWEEN …) |
| q19 | A | Price quartiles of shops within each state | NTILE(4) |
| q20 | C | Running cumulative change since Oct 2025 | SUM() OVER, LN/EXP |
| q21 | C | Do festive staples rise in the 2 weeks before each festival? | date windows, matched pairs |
| q22 | A | Which states see the biggest festive moves | RANK over GROUP BY |
| q23 | C | Price spikes above an item's recent normal | AVG/STDDEV OVER |
| q24 | B | How often each shop changes its price | LAG + COUNT of changes |
| q25 | B | First and latest price per shop and item | FIRST_VALUE / LAST_VALUE, frames |
| q26 | A | One summary by state, by shop type and in total | GROUPING SETS |
| q27 | All | Sense check against official CPI food inflation by state | JOIN to reference data, CORR |
| q28 | B | Shops with months missing from their reporting | generate_series + anti-join |
| q29 | C | Items with the most and least stable prices | coefficient of variation |
| q30 | All | The three headline findings as one report table | chained CTEs, UNION ALL |
| q31 | A | KPI checks: price-control adherence (coarse sugar, packet cooking oil) and district monitoring coverage | CASE inside AVG, UNION ALL, CTEs, COUNT(DISTINCT) |

## Which questions each stakeholder should read first

The shortest path through the queries for each reader.

| Stakeholder | Start with | Then |
|---|---|---|
| A. KPDN | q09 basket by state, q10 districts, q06 thin coverage, q31 KPI checks | q21 and q22 festive effect, q27 CPI check |
| B. Retailer | q03 and q12 shop formats, q11 chains | q16 price leaders, q24 re-pricing behaviour |
| C. Procurement | q13 and q14 what changed and where | q29 stability, q23 spikes, q18 staples trend |
