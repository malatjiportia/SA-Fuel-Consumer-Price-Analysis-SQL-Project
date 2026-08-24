# SA Fuel & Consumer Price Analysis

SQL project analysing South African petrol/diesel prices alongside a basic food basket, CPI, and unemployment across four provinces (Gauteng, Limpopo, Western Cape, KwaZulu-Natal) from **January 2021 to April 2024** (40 monthly observations per province, 160 rows total).

## What this project shows

- **Data cleaning in SQL**: identifying and fixing 9 data quality issues (inconsistent formats, duplicates, an outlier, a missing value, text-stored numbers) via a documented, auditable pipeline — plus a 10th issue (a mislabeled column pair) caught independently during QA.
- **Analytical SQL**: 22 queries across three tiers — descriptive summaries (GROUP BY), window functions (LAG, RANK, running totals), and statistical/economic insight queries (correlation, before/after event comparison, a composite stress index).
- **Reporting**: translating query output into a narrative report with quantified, defensible findings and recommendations — not just numbers, but what they mean and what to do next.

## Files in this repo

| File | Description |
|---|---|
| `Sa Fuel Prices.sql` | Source SQL — schema, data quality log, cleaning pipeline, and all 22 analytical queries (A1–A8, B1–B8, C1–C6). |
| `SA_Fuel_Prices_Portfolio_Report.pdf` | Main deliverable — executive summary, methodology, 5 key insights with figures, recommendations, and limitations. |
| `SA_Fuel_Prices_Methodology_Memo.docx` | Standalone technical memo documenting every cleaning decision and how each query was built, so the analysis is fully reproducible. |
| `SA_fuel_price_consumer_goods_RAW.xlsx` | dataset (160 records) |

## Contents

| Section | What it does |
|---|---|
| 1 — Schema | Creates `fuel_consumer_cleaned` (typed, indexed, with two generated columns) and `data_quality_log` |
| 2 — Data quality log | Documents 9 known issues in the raw CSV and how each was resolved |
| 3 — Load cleaned data | Inserts the 160 already-cleaned rows |
| 6 — Core analysis (A1–A8) | Summary stats: province averages, monthly trend, annual summary, basket comparison, most/least expensive months, diesel-petrol gap, DQ issue summary |
| 7 — Advanced analysis (B1–B8) | YoY change, Limpopo-Gauteng premium, affordability index, basket-petrol correlation, running fuel spend, quarterly rollup, province ranking, rolling average |
| 8 — Economic insights (C1–C6) | Before/after peak comparison, Pearson correlation, fare elasticity, economic stress index, Western Cape premium, pressure-score ranking |

### Generated columns
- `basic_basket_zar` — bread + (maize meal ÷ 4) + chicken + (milk × 4) + eggs
- `petrol_affordability` — petrol price as % of `cpi_index`

## Known issues

**From the original data-quality log (9 issues, all resolved in this file):** date-format inconsistency, a `KZN` abbreviation, city-casing typos, four fuel-type name variants, a duplicate `ULP 93` row, one exact duplicate row, a diesel outlier (R99.85 → corrected to R19.12), one missing petrol price (imputed), and prices originally stored as text.

## Headline findings

- **National petrol rose 59.9%** (R15.12 → R24.17/L, Jan-2021 to Apr-2024), but it wasn't linear: +34% in 2022, **‑3.5% in 2023**, +3.4% in 2024.
- **The food basket rose 75.7%** (R295 → R518) over the same window and climbed every quarter with no 2023 relief — unlike petrol.
- **Limpopo pays a consistent premium** over Gauteng (R0.13/L in 2021, growing to ~R0.19–0.20/L by 2023–24) and has the highest average fuel and chicken prices of the four provinces.
- **Western Cape's food basket is the most expensive** (~5% above Gauteng), driven by bread, milk, and transport fare — not fuel, which is priced almost identically to Gauteng and KZN.
- **Jun–Aug 2022 marks a real inflection point:** comparing 6 months before vs after, petrol +9.4%, basket +10.2%, chicken +12.3%, bread +9.2% — food moved almost in step with fuel, not with a long lag.
- **Transport fares move in lumps, not smoothly** — many months show 0% fare change even with a petrol move, followed by a larger step adjustment (e.g. Dec-2021: petrol +2.1%, fare +8.9%).

## A data quality catch worth flagging

During QA, the `cpi_index` and `unemployment_pct` columns in the source data were found to be transposed relative to their names and expected value ranges. This was identified by checking that the column named `unemployment_pct` was constant across all provinces within a month (the signature of a national CPI print, not a province-level unemployment rate) — and corrected throughout every downstream figure, with the finding documented rather than silently fixed. Full detail is in the methodology memo, Section 3.1.

## Tools

SQL (MySQL syntax — CTEs, window functions, generated/stored columns, CASE-based cleaning logic), Excel (formula-driven analysis workbook), Word (report and memo).

## Author

Portia — data analyst portfolio project, part of ongoing job search.
