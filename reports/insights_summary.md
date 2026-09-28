# Maven Fuzzy Factory: funnel and A/B test review

Every number comes from `sql/03-05`, `notebooks/01_eda.ipynb` or `notebooks/02_ab_tests.ipynb`.
"CY" means the last 12 full months (March 2014 to February 2015).

---

## 1. Situation

**A fast-growing online retailer that still relies on one paid channel.**

- Three years of data (2012-03-19 to 2015-03-19): 472,871 sessions, 32,313 orders, $1.94M revenue, 4 products.
- Growth, April 2014 to February 2015 vs a year earlier: sessions +90.0%, orders +119.6%, revenue +155.0%.
  Orders and revenue grew faster than traffic because conversion rose from 6.59% to 7.62% and revenue per session
  from $3.62 to $4.86.
- 71.4% of all sessions came from paid nonbrand search (gsearch and bsearch).
- Leadership's questions: which channels and devices bring buyers, where visitors drop out, whether the website tests
  really worked, and what to change next.

---

## 2. Key findings

### 2.1 Paid nonbrand search pays the bills but converts worst among search channels

| Channel | Sessions | Share | Conversion | Revenue / session |
|---|---:|---:|---:|---:|
| paid_nonbrand | 337,615 | 71.4% | 6.71% | $4.00 |
| organic_search | 43,411 | 9.2% | 7.51% | $4.53 |
| paid_brand | 41,243 | 8.7% | 7.79% | $4.72 |
| direct_type_in | 39,917 | 8.4% | 7.15% | $4.37 |
| paid_social | 10,685 | 2.3% | 3.21% | $2.08 |

- Paid nonbrand brings 69.6% of revenue ($1.35M) but has the lowest conversion of the search channels.
- Brand, organic and direct (visitors who already know the store) grew from 16.1% of sessions in Apr12-Feb13 to 30.8%
  in Apr14-Feb15. Paid nonbrand fell from 83.9% to 66.9%. The brand is getting stronger, and the business is less
  exposed to paid search costs.
- Paid social is the weakest channel: 3.21% conversion, $2.08 per session, and 77.6% of its visitors leave on the
  landing page.

### 2.2 Mobile is a third of traffic but a seventh of revenue

- Mobile: 30.8% of sessions, 14.1% of revenue. Conversion 3.09% vs 8.50% on desktop; revenue per session
  $1.87 vs $5.09.
- In CY, mobile and desktop orders are worth the same (AOV $63.86 vs $63.84). The gap is entirely in how many
  mobile visitors buy, not in how much they spend.
- Mobile is weaker at every funnel step. The biggest gaps are products to product page (68.2% vs 84.9%) and
  shipping to billing (70.7% vs 83.0%).
- The gap holds in every channel: desktop converts at 8.1-10.4% in the search and direct channels and 5.0% in paid social;
  mobile at 2.9-3.4% (0.8% in paid social).

### 2.3 The biggest funnel leak is between product page and cart

| Step | Sessions | % of previous step |
|---|---:|---:|
| Landing page | 472,871 | |
| Products | 261,231 | 55.2% |
| Product page | 210,214 | 80.5% |
| **Cart** | **94,953** | **45.2%** |
| Shipping | 64,484 | 67.9% |
| Billing | 52,058 | 80.7% |
| Order | 32,313 | 62.1% |

- 115,261 sessions viewed a product and left without adding to cart. It is the biggest drop for both devices and for
  every channel except paid social, where the landing page is worse.
- Second: 44.8% of sessions leave from the landing page without reaching /products.
- Third: billing to order (62.1%), even after /billing-2 improved it.

### 2.4 The website tests: two clear wins, one clear loss, two too small to call

| Test | Segment | Conversion A to B | Lift | p-value | Verdict |
|---|---|---|---:|---:|---|
| T1 /home vs /lander-1 | gsearch nonbrand | 3.22% to 4.03% | +25.2% | 0.137 | not significant (underpowered) |
| T2 /lander-1 vs /lander-2 | paid nonbrand | 5.77% to 6.38% | +10.6% | 0.201 | not significant (underpowered) |
| T3 /billing vs /billing-2 | reached billing | 45.1% to 62.1% | +37.7% | < 0.001 | **B wins** |
| T4 /lander-2 vs /lander-4 | paid nonbrand desktop | 8.88% to 7.54% | -15.1% | < 0.001 | **A wins** |
| T5 /lander-2 vs /lander-5 | paid nonbrand desktop | 8.37% to 10.02% | +19.7% | < 0.001 | **B wins** |

- Each test was analysed only for the days both pages were live and only for the segment it ran on.
  The traffic splits were close to 50/50 (all SRM p-values >= 0.44), and device and source mix was balanced in every test,
  so there is no Simpson's paradox.
- /billing-2 and /lander-5 held up after rollout: 63.3% and 9.89% conversion in the next 8 weeks, vs 62.1% and
  10.02% during the tests. No novelty effect.
- /lander-1 and /lander-2 cut bounce significantly (by 5.6 and 6.2 points). Their conversion gains could not be
  confirmed: the tests could only detect lifts of about 50% and 24%, and would have needed 3.6x and 4.8x more traffic.
- After a Holm correction for running five tests, T3, T4 and T5 stay significant.
- At test-period traffic, the two winners are worth about +289 orders and +$15,500 a month.

### 2.5 Bigger baskets and more products lifted order value

- AOV was $49.99 until September 2013 (one product, one item per order). It was $62.80-$64.49 per quarter from Q2 2014.
- The cart cross-sell launched on 2013-09-25. In the month after, AOV went from $51.42 to $54.25, and cart-to-shipping
  did not fall (67.16% to 68.41%). The cross-sell added value without scaring buyers off (a before/after reading,
  not a controlled test).
- Since the Mini Bear got its own page (2014-12-05), 38.6% of Mr. Fuzzy orders include a second item, and the
  Mini Bear is added to 20-22% of orders for the other three products.
- Revenue per session tripled from $1.52 (Q2 2012) to $4.93 (Q4 2014).

### 2.6 A product quality problem in August and September 2014

- The Original Mr. Fuzzy (62.5% of revenue) had a refund rate of 13.8% in August 2014 and 13.3% in September 2014,
  against 5.11% for the product overall. That was 272 refunded items and $13,597 in two months. It fell back to 2.5%
  in October 2014.
- The Birthday Sugar Panda has the highest ongoing refund rate (6.04%). The Mini Bear has the lowest (1.28%) and a
  68% margin.

---

## 3. Recommendations

**Pages**
1. Keep /billing-2 and /lander-5 (both are live). Do not bring back /lander-4.
2. Run a proper A/B test on mobile. Mobile nonbrand traffic moved to /lander-3 in 2013 with no control group,
   and it has never been tested since.

**Funnel**
3. Make the product page to cart step the top priority: add reviews, show shipping and returns information, and make the
   add-to-cart button prominent. Test each change.
4. Simplify mobile checkout (fewer fields, one page for shipping and billing, wallet payments). Mobile loses more
   visitors than desktop at every step after the cart.

**Budget** (no cost data, so these are value-per-click guides, not ROI numbers)
5. Paid nonbrand, by device: in CY a desktop nonbrand session is worth $5.94 and a mobile one $2.31, about 61% less.
   Set a mobile bid adjustment of about -60% until mobile conversion improves, and move the savings to desktop
   nonbrand, where value per session keeps rising.
6. Paid social: stop mobile social (CY revenue per session $0.74, conversion 1.08%). Keep desktop_targeted only if
   its cost per click is well below $3.27 of revenue per session.
7. Keep investing in what grows brand, organic and direct traffic (SEO, email, word of mouth). These visitors convert best
   (10.3-10.9% on desktop in CY) and cost little or nothing per visit.

**Product**
8. Audit the Mr. Fuzzy supplier for the August and September 2014 batch, and set a monthly refund-rate alert at 1.5x each
   product's normal rate (the rule used in `sql/05_product_and_revenue.sql`).
9. Keep pushing the Mini Bear as the cross-sell item: low refunds, high margin, and it already attaches to one in
   five orders.

---

## 4. Expected impact

| Lever | Estimate | Basis |
|---|---|---|
| /billing-2 + /lander-5 (done) | about +289 orders, +$15,500 per month | test lift x test-period traffic |
| +1 point on product page to cart | about +419 orders, +$26,700 per year | CY product page sessions (120,490) x 1 point x CY cart-to-order rate (34.8%) x CY AOV ($63.84) |
| Close half the mobile checkout gap | about +535 orders, +$34,200 per year | mobile shipping-to-order from 39.1% to 46.6% (half way to desktop's 54.1%) x CY mobile shipping sessions (7,096) x AOV |
| Mobile bid adjustment | not quantifiable | needs cost-per-click data |

The last three rows are scenarios, not measured results. They assume the other funnel rates stay the same.

---

## 5. Risks and data limitations

- **No cost data.** Without ad spend we can't compute ROAS or cost per order, so the channel advice uses revenue per
  session only.
- **Before/after comparisons are not causal.** The /lander-3 switch and the cross-sell launch have no control group.
- **Impact estimates** assume the test lift stays constant and use test-period traffic. Traffic has grown since, so the
  monthly value is probably higher today, but the lift itself may drift.
- **Underpowered tests** (T1, T2): "not significant" means "not enough data", not "no effect".
- **Partial months:** March 2012 and March 2015 are partial and are excluded from trends and YoY comparisons.
- **Late refunds:** refunds run to 2015-04-01, so the latest months may still be missing some.
- **Cookie-based users:** `user_id` identifies a browser, so the same person on two devices counts as two users,
  and the repeat-session share is understated.
- **Test independence:** the tests treat sessions as independent. Paid nonbrand sessions are all first visits,
  which keeps this reasonable for the landing page tests.

---

## 6. Next tests to run

Sample sizes use 80% power and alpha = 0.05 (two-sided). Durations assume a 50/50 split at CY volumes.

| # | Test | Segment and baseline | Target lift | Sessions per arm | Duration |
|---|---|---|---:|---:|---:|
| 1 | Product page redesign (reviews, shipping info, prominent add-to-cart) | all product page views, 45.4% to cart | +5% | 7,577 | about 1.5 months |
| 2 | New mobile landing page vs /lander-3 | paid nonbrand mobile, 3.61% conversion | +20% | 11,470 | about 5.4 months |
| 3 | One-page mobile checkout | mobile shipping sessions, 39.1% to order | +10% | 2,487 | about 8.4 months |
| 4 | Paid social landing page | desktop social, 30.9% landing to products | +20% | 920 | about 1.6 months at the Aug-Dec 2014 pace |
| 5 | Cross-sell on the product page as well as the cart | orders, 38.6% multi-item for Mr. Fuzzy | TBD | TBD | TBD |

Tests 2 and 3 are slow at current mobile volume. Either make the change bold enough to target a bigger lift, or use
bounce rate or next-step click-through as the primary metric, since those need far fewer sessions.
Fix the sample size before launch and don't stop early.
