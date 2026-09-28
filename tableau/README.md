# Tableau Public dashboard: build guide

Tableau Public cannot connect to PostgreSQL, so `src/export_for_bi.py` writes the data to CSV:

```bash
source .venv/bin/activate
python src/export_for_bi.py      # re-run whenever the database changes
```

| File | Grain | Used for |
|---|---|---|
| `data/processed/daily_summary.csv` | day x channel x source x device x landing page x new/repeat | Executive Overview, Channels & Devices |
| `data/processed/funnel_steps.csv` | month x channel x device x funnel step (long format) | Conversion Funnel |
| `data/processed/product_monthly.csv` | month x product | optional product page |
| `data/processed/ab_test_results.csv` | one row per test | A/B Test Results (p-value, lift, impact) |
| `data/processed/ab_test_variants.csv` | one row per test x variant, with 95% CI | A/B Test Results (CI chart) |

`daily_summary` holds counts (sessions, orders, bounces, step counts, revenue), never rates. Every rate is rebuilt
in Tableau as `SUM(numerator) / SUM(denominator)`, so it stays correct at any level of aggregation. Averaging
pre-computed rates would weight a 5-session row the same as a 5,000-session row.

---

## 1. Connect the data: relationships vs joins

- **Join** (physical layer, double-click into a table): merges tables into one flat table *before* analysis.
  If the tables have different grains, rows get duplicated. For example, joining `daily_summary` to `funnel_steps`
  on month, channel and device would repeat every daily row 7 times (once per funnel step), and SUM(sessions)
  would be 7x too high.
- **Relationship** (logical layer, the "noodle" on the canvas): tables keep their own grain, and Tableau joins them at
  query time using only the fields a sheet actually uses. There's no duplication, and each measure aggregates at
  its own level.

**What to use here:** each CSV is already a complete, self-contained table at its own grain, so add each one as its own
**data source** (Data > New Data Source > Text file) with no joins. The only natural key between files is
`product_id` (`product_monthly` to `products`), and `product_monthly` already contains `product_name`, so no join is needed.
To make one filter drive sheets from different data sources, use a dashboard **filter action** with mapped fields
(section 5). `channel_group` and `device_type` have the same names in `daily_summary` and `funnel_steps`, so
Tableau matches them automatically.

After connecting `daily_summary`:
- Check the data types: `session_date` and `session_month` = Date; `is_full_month` = Boolean; counts = Number (whole).
- Rename for display (right-click > Rename): `channel_group` to Channel, `device_type` to Device, `landing_page` to Landing Page.

---

## 2. Colors (use the same everywhere)

Set these once per field: right-click the field > Default Properties > Color, then click each item and enter the hex code
("Select color > More colors").

| Field value | Hex |
|---|---|
| paid_nonbrand | `#2a78d6` |
| paid_brand | `#eb6834` |
| organic_search | `#1baf7a` |
| direct_type_in | `#eda100` |
| paid_social | `#e87ba4` |
| desktop | `#2a78d6` |
| mobile | `#eb6834` |
| Variant A (control) | `#8a8984` |
| Variant B (new page) | `#2a78d6` |
| Highlight (biggest drop, losing test) | `#e34948` |

Optional: to get these as a named palette, add this inside `<preferences>` in
`~/Documents/My Tableau Public Repository/Preferences.tps` and restart Tableau Public:

```xml
<color-palette name="Fuzzy Factory" type="regular">
  <color>#2a78d6</color>
  <color>#eb6834</color>
  <color>#1baf7a</color>
  <color>#eda100</color>
  <color>#e87ba4</color>
  <color>#8a8984</color>
  <color>#e34948</color>
</color-palette>
```

Worksheet background: `#fcfcfb`. Gridlines: light gray, thin. Remove column/row dividers on KPI cards.

---

## 3. Calculated fields (data source: daily_summary)

Create each with Analysis > Create Calculated Field.

```
// Conversion Rate            (format: Percentage, 2 decimals)
SUM([orders]) / SUM([sessions])

// Revenue per Session        (format: Currency, 2 decimals)
SUM([revenue_usd]) / SUM([sessions])

// AOV                        (format: Currency, 2 decimals)
SUM([revenue_usd]) / SUM([orders])

// Bounce Rate                (format: Percentage, 1 decimal)
SUM([bounces]) / SUM([sessions])

// Gross Margin               (format: Currency, 0 decimals)
SUM([revenue_usd]) - SUM([cogs_usd])
```

### YoY %: two approaches

**A. Table calculation** (for the monthly trend line)

```
// Sessions YoY % (table calc)
(SUM([sessions]) - LOOKUP(SUM([sessions]), -12)) / ABS(LOOKUP(SUM([sessions]), -12))
```
Put continuous `MONTH(session_month)` on Columns, then Edit Table Calculation > Compute Using > session_month.
`LOOKUP(..., -12)` reads the value 12 marks to the left, so it only works if every month is in the view. A date
filter that removes the prior year makes it return null.

**B. Fixed periods with an LOD anchor** (for KPI cards)

```
// Max Full Month
{ FIXED : MAX(IF [is_full_month] THEN [session_month] END) }

// Is Current Period          (last 12 full months: Mar 2014 - Feb 2015)
[session_month] > DATEADD('month', -12, [Max Full Month]) AND [session_month] <= [Max Full Month]

// Is Prior Period            (the 12 months before: Mar 2013 - Feb 2014)
[session_month] > DATEADD('month', -24, [Max Full Month])
AND [session_month] <= DATEADD('month', -12, [Max Full Month])

// Sessions CY
SUM(IF [Is Current Period] THEN [sessions] END)
// Sessions PY
SUM(IF [Is Prior Period] THEN [sessions] END)
// Sessions YoY %
([Sessions CY] - [Sessions PY]) / [Sessions PY]

// Orders CY / Orders PY / Orders YoY %           same pattern with [orders]
// Revenue CY / Revenue PY / Revenue YoY %        same pattern with [revenue_usd]

// Conversion CY
[Orders CY] / [Sessions CY]
// Conversion PY
[Orders PY] / [Sessions PY]
// Conversion YoY (pp)        (format: Number, 2 decimals, suffix " pp")
([Conversion CY] - [Conversion PY]) * 100

// RPS CY
[Revenue CY] / [Sessions CY]
// RPS PY
[Revenue PY] / [Sessions PY]
// RPS YoY %
([RPS CY] - [RPS PY]) / [RPS PY]
```

**Which is better here:** use B for the KPI cards. A KPI card is a single number with no months in the view, so
`LOOKUP` has nothing to look back over. B gives the same answer whatever is on the sheet. The `FIXED` anchor is
computed before dimension filters, so picking a channel doesn't move the comparison window, and both periods
are filtered to that channel consistently. Use A for the monthly YoY line, where months are in the view anyway.

Expected values to check the cards against (all channels, from SQL):

| KPI | CY (Mar 2014 - Feb 2015) | PY (Mar 2013 - Feb 2014) | YoY |
|---|---:|---:|---:|
| Sessions | 251,427 | 130,322 | +92.9% |
| Orders | 19,022 | 8,563 | +122.1% |
| Conversion rate | 7.57% | 6.57% | +1.0 pp |
| Revenue | $1,214,375 | $469,428 | +158.7% |
| Revenue per session | $4.83 | $3.60 | +34.1% |

### Metric switch parameter

Create Parameter **Select Metric**: Data type String, Allowable values List:
`Sessions`, `Orders`, `Conversion Rate`, `Revenue`. Right-click it > Show Parameter.

```
// Selected Metric
CASE [Select Metric]
    WHEN "Sessions" THEN SUM([sessions])
    WHEN "Orders" THEN SUM([orders])
    WHEN "Conversion Rate" THEN SUM([orders]) / SUM([sessions])
    WHEN "Revenue" THEN SUM([revenue_usd])
END

// Selected Metric Label      (use in tooltips and labels, since one number format can't fit all four)
CASE [Select Metric]
    WHEN "Conversion Rate" THEN STR(ROUND([Selected Metric] * 100, 2)) + "%"
    WHEN "Revenue" THEN "$" + STR(ROUND([Selected Metric] / 1000, 1)) + "k"
    ELSE STR(ROUND([Selected Metric], 0))
END

// Metric Title               (put in the sheet title: Insert > Metric Title)
"Monthly " + [Select Metric]
```

### Channel share

```
// Share of Sessions          (compute using: channel_group)
SUM([sessions]) / TOTAL(SUM([sessions]))
```

### Funnel fields (data source: funnel_steps)

```
// Step Sessions
SUM([sessions])

// % of Previous Step         (compute using: step_name; format Percentage 1 decimal)
SUM([sessions]) / LOOKUP(SUM([sessions]), -1)

// % of Landing               (compute using: step_name)
SUM([sessions]) / LOOKUP(SUM([sessions]), FIRST())

// Drop-off %                 (compute using: step_name)
1 - [% of Previous Step]

// Is Biggest Drop            (compute using: step_name; put on Color)
IF [Drop-off %] = WINDOW_MAX([Drop-off %]) THEN "Biggest drop" ELSE "Other steps" END
```
Color: "Biggest drop" `#e34948`, "Other steps" `#2a78d6`. With all data the biggest drop is product page to cart
(45.2% continue); on mobile the numbers are 145,844 > 68,906 > 47,000 > 19,798 > 11,792 > 8,336 > 4,508.

### A/B fields (data sources: ab_test_variants and ab_test_results)

```
// CI Width                   (ab_test_variants)
[conv_ci_high] - [conv_ci_low]

// Lift Label                 (ab_test_results)
IF [conv_rel_lift] >= 0 THEN "+" ELSE "" END + STR(ROUND([conv_rel_lift] * 100, 1)) + "%"

// P-value Label              (ab_test_results)
IF [conv_p_value] < 0.001 THEN "< 0.001" ELSE STR(ROUND([conv_p_value], 3)) END

// Monthly Revenue Impact     (ab_test_results; format Currency 0 decimals)
[incr_revenue_month]
```

---

## 4. Dashboards

Size: Dashboard > Size > Fixed, 1200 x 800 (Desktop layout). Title in the top-left, filters in one row under the title.

### Dashboard 1: Executive Overview

```
+--------------------------------------------------------------------------+
| Maven Fuzzy Factory: Executive Overview        [Channel v] [Metric v]    |
+-------------+-------------+-------------+-------------+-----------------+
|  Sessions   |   Orders    | Conversion  |   Revenue   | Revenue/Session |
|  251,427    |   19,022    |   7.57%     |  $1.21M     |    $4.83        |
|  +92.9% YoY | +122.1% YoY |  +1.0 pp    | +158.7% YoY |   +34.1% YoY    |
+-------------+-------------+-------------+-------------+-----------------+
|  Monthly <metric> (line, one line per channel or total)                  |
|                                                                          |
+--------------------------------------------------------------------------+
```

- **KPI card sheet** (one per KPI): drag `Sessions CY` to Text, add `Sessions YoY %` to Text. Edit the text to
  two lines (big number 24pt bold, YoY line 11pt gray). Mark type Text. Hide headers.
- **Trend sheet**: Columns = `MONTH(session_month)` (continuous); Rows = `Selected Metric`; Color = `channel_group`.
  Filter `is_full_month` = True. Tooltip: `<channel_group>`, `<MONTH(session_month)>`, `<Selected Metric Label>`.
- Filters: `channel_group` as a single-value dropdown, "Apply to Worksheets > All using this data source".
  Show the `Select Metric` parameter.

### Dashboard 2: Channels & Devices

```
+--------------------------------------------------------------------------+
| Channels & Devices                                  [Date range]         |
+-----------------------------------+--------------------------------------+
| Highlight table                   | Channel mix over time (100% area)    |
|            desktop    mobile      |                                      |
| paid_nonb   8.09%     3.18%       |                                      |
| paid_brand 10.37%     3.01%       |                                      |
| organic     9.96%     2.94%       |                                      |
| direct      9.81%     3.44%       |                                      |
| social      4.99%     0.83%       |                                      |
+-----------------------------------+--------------------------------------+
| Revenue per session by channel x device (same highlight table layout)    |
+--------------------------------------------------------------------------+
```

- **Highlight table**: Rows = `channel_group`, Columns = `device_type`, Mark = Square, Color = `Conversion Rate`
  (sequential blue, 5 steps), Label = `Conversion Rate` and `Revenue per Session`.
- **Channel mix**: Columns = `MONTH(session_month)`, Rows = `Share of Sessions` (compute using channel_group),
  Mark = Area, Color = `channel_group`. Filter `is_full_month` = True.

### Dashboard 3: Conversion Funnel

```
+--------------------------------------------------------------------------+
| Conversion Funnel                              [Device v] [Channel v]    |
+--------------------------------------------------------------------------+
| 1. Landing page  ##########################################  472,871     |
| 2. Products      ########################  55.2%                         |
| 3. Product page  ###################  80.5%                              |
| 4. Cart          ########  45.2%   <- red: biggest drop                  |
| 5. Shipping      ######  67.9%                                           |
| 6. Billing       #####  80.7%                                            |
| 7. Order         ###  62.1%                                              |
+--------------------------------------------------------------------------+
| Step-to-step % by device (text table: step_name x device_type)           |
+--------------------------------------------------------------------------+
```

- Data source `funnel_steps`. Rows = `step_name` (sorted by `step_num`), Columns = `Step Sessions`, Mark = Bar,
  Color = `Is Biggest Drop`, Label = `Step Sessions` and `% of Previous Step`.
- Filters `device_type` and `channel_group` (single value dropdown with "All"). The table calcs recompute, so the red bar
  moves if a segment's biggest drop is elsewhere (for paid_social it moves to landing > products).
- Optional centered funnel: add a second bar with `-[Step Sessions]/2`. Simple left-aligned bars read better.

### Dashboard 4: A/B Test Results

```
+--------------------------------------------------------------------------+
| A/B Test Results                                                         |
+--------------------------------------------------------------------------+
| T1 /home vs /lander-1      A  |---o---|                                  |
|                            B     |---o---|                               |
| T2 ...                                                                   |
| T3 /billing vs /billing-2  A                  |--o--|                    |
|                            B                           |--o--|           |
| (conversion rate with 95% CI, gray = A, blue = B)                        |
+--------------------------------------------------------------------------+
| Test | Segment | Lift | p-value | Holm p | Monthly revenue impact | Decision |
+--------------------------------------------------------------------------+
```

- **CI chart** (`ab_test_variants`): Rows = `test_name`, `variant`. Columns = `conv_ci_low` and `conv_rate`.
  - First measure: Mark = Gantt Bar, Size = `CI Width`, Color = `variant`.
  - Second measure: Mark = Circle, Color = `variant`.
  - Right-click the second axis > Dual Axis, then **Synchronize Axis** (same scale on both, so this is one axis,
    not two) and hide the top header.
  - Tooltip: page, sessions, orders, conversion rate, CI.
- **Results table** (`ab_test_results`): Rows = `test`, `name`, `segment`, `decision`; Measure Values =
  `Lift Label`, `P-value Label`, `conv_p_holm`, `Monthly Revenue Impact`. Color `decision`:
  "B wins" blue, "A wins" red, "no significant difference" gray.
- Caption under the chart: "Impact = difference in revenue per session x segment sessions per month during the test."

### Dashboard 5: Insights & Recommendations

A text dashboard. Add a Text object with the key findings and recommendations from `reports/insights_summary.md`
(4-6 short bullets), and small images of the funnel and A/B chart if wanted (`images/funnel.png`,
`images/ab_test_results.png`).

---

## 5. Interactivity

- **Click a channel to filter everything:** on Dashboard 2, Dashboard > Actions > Add Action > Filter.
  Source sheet: highlight table. Run on: Select. Target: all sheets on dashboards 1-3. Target Filters: Selected Fields,
  `channel_group` > `channel_group` (map the field for each data source). Clearing the selection: Show all values.
- **Highlight action** on Dashboard 1: hover over a channel line to highlight it.
- **Tooltips:** edit every tooltip to one short sentence, e.g.
  `<channel_group> on <device_type>: <Conversion Rate> conversion from <SUM(sessions)> sessions`.
- **Navigation:** add Navigation buttons (Objects > Navigation) at the top of each dashboard, or publish as a Story.

## 6. Phone layout

On each dashboard: Device Preview > Phone > Add Phone Layout > Fit: Fit Width.
- Stack the KPI cards 2 per row (the 5th card full width), then the trend chart.
- Hide legends that repeat colors already labelled in the chart; keep one filter dropdown at the top.
- Funnel: keep the bar chart and drop the by-device table.
- A/B: keep the CI chart; show the results table below it with only Test, Lift, p-value and Decision.

## 7. Publish and capture

1. File > Save to Tableau Public As... > sign in > name: `Maven Fuzzy Factory - Funnel and A-B Test Analysis`.
2. In the browser that opens: Edit Details > add a 1-2 line description and the GitHub link; turn on
   "Show workbook sheets as tabs" if you didn't add navigation buttons.
3. Copy the URL into the README (Links section).
4. Screenshots: on Tableau Public, press `Cmd + Shift + 4`, then Space, then click the browser window, or use the
   viz toolbar Download > Image. Save as `images/dashboard_1_overview.png`, `images/dashboard_2_channels.png`,
   `images/dashboard_3_funnel.png`, `images/dashboard_4_ab_tests.png`.
5. Walkthrough GIF (60-90 seconds): `Cmd + Shift + 5` > Record Selected Portion around the viz. Script:
   overview KPIs (10s) > switch the metric parameter (10s) > click paid_nonbrand in the highlight table (10s) >
   funnel filtered to mobile, showing the red step (15s) > A/B CI chart and results table (20s) > recommendations (10s).
   Convert (needs `brew install ffmpeg`):
   ```bash
   ffmpeg -i walkthrough.mov -vf "fps=10,scale=1200:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" \
          -loop 0 images/dashboard_walkthrough.gif
   ```
   Keep it under about 10 MB so it loads in the GitHub README.
