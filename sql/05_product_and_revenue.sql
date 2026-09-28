-- Product, cross-sell, refund and revenue quality analysis.

-- 11a. Product summary: items sold, revenue, margin
SELECT
    p.product_id,
    p.product_name,
    p.created_at::DATE AS launched,
    COUNT(*) AS items_sold,
    SUM(i.price_usd) AS revenue,
    SUM(i.price_usd - i.cogs_usd) AS margin,
    ROUND(100.0 * SUM(i.price_usd - i.cogs_usd) / SUM(i.price_usd), 1) AS margin_pct,
    ROUND(100.0 * SUM(i.price_usd) / SUM(SUM(i.price_usd)) OVER (), 1) AS share_of_revenue_pct
FROM order_items i
JOIN products p ON p.product_id = i.product_id
GROUP BY p.product_id, p.product_name, p.created_at
ORDER BY p.product_id;

-- 11b. Monthly revenue, margin and items by product, plus orders and AOV by primary product.
-- Item-level numbers credit each product for what it sold; order-level numbers (orders, AOV)
-- credit the whole order to its primary product.
WITH item_monthly AS (
    SELECT
        DATE_TRUNC('month', created_at)::DATE AS month,
        product_id,
        COUNT(*) AS items_sold,
        SUM(price_usd) AS revenue,
        SUM(price_usd - cogs_usd) AS margin
    FROM order_items
    GROUP BY 1, 2
),
order_monthly AS (
    SELECT
        DATE_TRUNC('month', created_at)::DATE AS month,
        primary_product_id AS product_id,
        COUNT(*) AS orders_as_primary,
        ROUND(AVG(price_usd), 2) AS aov
    FROM orders
    GROUP BY 1, 2
)
SELECT
    i.month,
    p.product_name,
    i.items_sold,
    i.revenue,
    i.margin,
    COALESCE(o.orders_as_primary, 0) AS orders_as_primary,
    o.aov
FROM item_monthly i
JOIN products p ON p.product_id = i.product_id
LEFT JOIN order_monthly o ON o.month = i.month AND o.product_id = i.product_id
ORDER BY i.month, i.product_id;


-- 12a. Cross-sell: for each primary product, which other products were added and at what rate.
-- Only orders from 2014-12-05 on: before that the Mini Bear had no product page and could only be
-- added at the cart, so it could not be a primary product. From then on every pair had a fair chance.
WITH orders_window AS (
    SELECT order_id, primary_product_id
    FROM orders
    WHERE created_at >= '2014-12-05'
),
cross_items AS (
    SELECT o.order_id, o.primary_product_id, i.product_id AS cross_product_id
    FROM orders_window o
    JOIN order_items i ON i.order_id = o.order_id AND i.is_primary_item = 0
)
SELECT
    o.primary_product_id,
    COUNT(DISTINCT o.order_id) AS orders,
    COUNT(DISTINCT c.order_id) FILTER (WHERE c.cross_product_id = 1) AS x_mr_fuzzy,
    COUNT(DISTINCT c.order_id) FILTER (WHERE c.cross_product_id = 2) AS x_love_bear,
    COUNT(DISTINCT c.order_id) FILTER (WHERE c.cross_product_id = 3) AS x_sugar_panda,
    COUNT(DISTINCT c.order_id) FILTER (WHERE c.cross_product_id = 4) AS x_mini_bear,
    ROUND(100.0 * COUNT(DISTINCT c.order_id) FILTER (WHERE c.cross_product_id = 1) / COUNT(DISTINCT o.order_id), 1) AS x_mr_fuzzy_pct,
    ROUND(100.0 * COUNT(DISTINCT c.order_id) FILTER (WHERE c.cross_product_id = 2) / COUNT(DISTINCT o.order_id), 1) AS x_love_bear_pct,
    ROUND(100.0 * COUNT(DISTINCT c.order_id) FILTER (WHERE c.cross_product_id = 3) / COUNT(DISTINCT o.order_id), 1) AS x_sugar_panda_pct,
    ROUND(100.0 * COUNT(DISTINCT c.order_id) FILTER (WHERE c.cross_product_id = 4) / COUNT(DISTINCT o.order_id), 1) AS x_mini_bear_pct,
    ROUND(100.0 * COUNT(DISTINCT c.order_id) / COUNT(DISTINCT o.order_id), 1) AS any_cross_sell_pct
FROM orders_window o
LEFT JOIN cross_items c ON c.order_id = o.order_id
GROUP BY o.primary_product_id
ORDER BY o.primary_product_id;

-- 12b. Cross-sell launch: two-item orders first appear on 2013-09-25, when a second product
-- could be added at the cart. Compare the month before and the month after (pre/post, not a controlled test).
SELECT
    CASE WHEN s.created_at < '2013-09-25' THEN '1_pre (2013-08-25 to 09-24)' ELSE '2_post (2013-09-25 to 10-24)' END AS period,
    COUNT(*) FILTER (WHERE s.saw_cart = 1) AS cart_sessions,
    ROUND(100.0 * SUM(s.saw_shipping) / SUM(s.saw_cart), 2) AS cart_to_shipping_pct,
    SUM(s.has_order) AS orders,
    ROUND(AVG(s.items_purchased), 3) AS items_per_order,
    ROUND(SUM(s.revenue_usd) / SUM(s.has_order), 2) AS aov,
    ROUND(SUM(s.revenue_usd) / COUNT(*) FILTER (WHERE s.saw_cart = 1), 2) AS revenue_per_cart_session
FROM v_sessions_enriched s
WHERE s.created_at >= '2013-08-25' AND s.created_at < '2013-10-25'
GROUP BY 1
ORDER BY 1;


-- 13a. Refund rate by product and month. A month is flagged when its refund rate is more than
-- 1.5x the product's overall rate (and the product sold at least 50 items that month).
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', i.created_at)::DATE AS month,
        i.product_id,
        COUNT(*) AS items_sold,
        COUNT(r.order_item_refund_id) AS items_refunded
    FROM order_items i
    LEFT JOIN order_item_refunds r ON r.order_item_id = i.order_item_id
    GROUP BY 1, 2
),
rates AS (
    SELECT
        month,
        product_id,
        items_sold,
        items_refunded,
        100.0 * items_refunded / items_sold AS refund_rate_pct,
        100.0 * SUM(items_refunded) OVER (PARTITION BY product_id)
              / SUM(items_sold) OVER (PARTITION BY product_id) AS product_avg_pct
    FROM monthly
)
SELECT
    month,
    product_id,
    items_sold,
    items_refunded,
    ROUND(refund_rate_pct, 2) AS refund_rate_pct,
    ROUND(product_avg_pct, 2) AS product_avg_pct,
    CASE WHEN refund_rate_pct > 1.5 * product_avg_pct AND items_sold >= 50 THEN 'CHECK' ELSE '' END AS flag
FROM rates
ORDER BY product_id, month;

-- 13b. Overall refund rate by product
SELECT
    p.product_name,
    COUNT(*) AS items_sold,
    COUNT(r.order_item_refund_id) AS items_refunded,
    ROUND(100.0 * COUNT(r.order_item_refund_id) / COUNT(*), 2) AS refund_rate_pct,
    COALESCE(SUM(r.refund_amount_usd), 0) AS refunded_usd
FROM order_items i
JOIN products p ON p.product_id = i.product_id
LEFT JOIN order_item_refunds r ON r.order_item_id = i.order_item_id
GROUP BY p.product_id, p.product_name
ORDER BY p.product_id;


-- 14a. Revenue per session by quarter: is traffic quality improving?
SELECT
    DATE_TRUNC('quarter', created_at)::DATE AS quarter,
    COUNT(*) AS sessions,
    SUM(has_order) AS orders,
    ROUND(100.0 * SUM(has_order) / COUNT(*), 2) AS conv_rate_pct,
    ROUND(SUM(revenue_usd) / NULLIF(SUM(has_order), 0), 2) AS aov,
    ROUND(SUM(revenue_usd) / COUNT(*), 2) AS revenue_per_session,
    ROUND(SUM(revenue_usd - cogs_usd - refund_usd) / COUNT(*), 2) AS net_margin_per_session
FROM v_sessions_enriched
GROUP BY 1
ORDER BY 1;

-- 14b. Revenue per session by quarter and channel (the paid nonbrand number is what bid decisions depend on)
SELECT
    DATE_TRUNC('quarter', created_at)::DATE AS quarter,
    ROUND(SUM(revenue_usd) FILTER (WHERE channel_group = 'paid_nonbrand')
        / NULLIF(COUNT(*) FILTER (WHERE channel_group = 'paid_nonbrand'), 0), 2) AS paid_nonbrand,
    ROUND(SUM(revenue_usd) FILTER (WHERE channel_group = 'paid_brand')
        / NULLIF(COUNT(*) FILTER (WHERE channel_group = 'paid_brand'), 0), 2) AS paid_brand,
    ROUND(SUM(revenue_usd) FILTER (WHERE channel_group = 'organic_search')
        / NULLIF(COUNT(*) FILTER (WHERE channel_group = 'organic_search'), 0), 2) AS organic_search,
    ROUND(SUM(revenue_usd) FILTER (WHERE channel_group = 'direct_type_in')
        / NULLIF(COUNT(*) FILTER (WHERE channel_group = 'direct_type_in'), 0), 2) AS direct_type_in,
    ROUND(SUM(revenue_usd) FILTER (WHERE channel_group = 'paid_social')
        / NULLIF(COUNT(*) FILTER (WHERE channel_group = 'paid_social'), 0), 2) AS paid_social
FROM v_sessions_enriched
GROUP BY 1
ORDER BY 1;
