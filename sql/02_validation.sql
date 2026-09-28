-- Validation checks after loading. Every "problem_rows" value should be 0.

-- 1. Row counts reconcile to the CSVs (expected = data rows in each raw file)
SELECT table_name, loaded_rows, expected_rows, loaded_rows = expected_rows AS matches
FROM (
    SELECT 'website_sessions' AS table_name, (SELECT COUNT(*) FROM website_sessions) AS loaded_rows, 472871 AS expected_rows
    UNION ALL SELECT 'website_pageviews', (SELECT COUNT(*) FROM website_pageviews), 1188124
    UNION ALL SELECT 'orders', (SELECT COUNT(*) FROM orders), 32313
    UNION ALL SELECT 'order_items', (SELECT COUNT(*) FROM order_items), 40025
    UNION ALL SELECT 'order_item_refunds', (SELECT COUNT(*) FROM order_item_refunds), 1731
    UNION ALL SELECT 'products', (SELECT COUNT(*) FROM products), 4
) counts;

-- 2. Orphan keys (the foreign keys already enforce these; this proves it explicitly)
SELECT 'orders without session' AS check_name, COUNT(*) AS problem_rows
FROM orders o
LEFT JOIN website_sessions s ON s.website_session_id = o.website_session_id
WHERE s.website_session_id IS NULL
UNION ALL
SELECT 'pageviews without session', COUNT(*)
FROM website_pageviews p
LEFT JOIN website_sessions s ON s.website_session_id = p.website_session_id
WHERE s.website_session_id IS NULL
UNION ALL
SELECT 'items without order', COUNT(*)
FROM order_items i
LEFT JOIN orders o ON o.order_id = i.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'refunds without item', COUNT(*)
FROM order_item_refunds r
LEFT JOIN order_items i ON i.order_item_id = r.order_item_id
WHERE i.order_item_id IS NULL
UNION ALL
SELECT 'orders without thank-you pageview', COUNT(*)
FROM orders o
WHERE NOT EXISTS (
    SELECT 1 FROM website_pageviews p
    WHERE p.website_session_id = o.website_session_id
      AND p.pageview_url = '/thank-you-for-your-order'
);

-- 3. Order revenue equals the sum of item revenue
WITH item_totals AS (
    SELECT order_id, SUM(price_usd) AS item_price, SUM(cogs_usd) AS item_cogs, COUNT(*) AS item_count
    FROM order_items
    GROUP BY order_id
)
SELECT
    COUNT(*) FILTER (WHERE o.price_usd <> t.item_price) AS price_mismatch,
    COUNT(*) FILTER (WHERE o.cogs_usd <> t.item_cogs) AS cogs_mismatch,
    COUNT(*) FILTER (WHERE o.items_purchased <> t.item_count) AS item_count_mismatch
FROM orders o
JOIN item_totals t ON t.order_id = o.order_id;

-- 4. Refunds never exceed the item price, and the refund's order_id matches the item's order
SELECT
    COUNT(*) FILTER (WHERE r.refund_amount_usd > i.price_usd) AS refund_above_price,
    COUNT(*) FILTER (WHERE r.refund_amount_usd < i.price_usd) AS partial_refunds,
    COUNT(*) FILTER (WHERE r.order_id <> i.order_id) AS order_id_mismatch,
    COUNT(*) FILTER (WHERE r.created_at < i.created_at) AS refund_before_order
FROM order_item_refunds r
JOIN order_items i ON i.order_item_id = r.order_item_id;

-- 5. Every session has at least one pageview
SELECT COUNT(*) AS sessions_without_pageviews
FROM website_sessions s
WHERE NOT EXISTS (
    SELECT 1 FROM website_pageviews p WHERE p.website_session_id = s.website_session_id
);

-- 6. The funnel is linear: no session reaches a step without the step before it
SELECT
    COUNT(*) FILTER (WHERE saw_product_page = 1 AND saw_products = 0) AS product_page_without_products,
    COUNT(*) FILTER (WHERE saw_cart = 1 AND saw_product_page = 0) AS cart_without_product_page,
    COUNT(*) FILTER (WHERE saw_shipping = 1 AND saw_cart = 0) AS shipping_without_cart,
    COUNT(*) FILTER (WHERE saw_billing = 1 AND saw_shipping = 0) AS billing_without_shipping,
    COUNT(*) FILTER (WHERE saw_thank_you = 1 AND saw_billing = 0) AS order_without_billing,
    COUNT(*) FILTER (WHERE saw_thank_you <> has_order) AS thank_you_vs_order_mismatch
FROM v_sessions_enriched;

-- 7. The view has one row per session and every session gets a channel group
SELECT
    COUNT(*) AS view_rows,
    COUNT(DISTINCT website_session_id) AS distinct_sessions,
    COUNT(*) FILTER (WHERE channel_group = 'other') AS unmapped_channel,
    SUM(revenue_usd) AS view_revenue,
    (SELECT SUM(price_usd) FROM orders) AS orders_revenue
FROM v_sessions_enriched;

-- 8. Channel group mapping (should match the Phase 1 source counts)
SELECT channel_group, utm_source, utm_campaign, http_referer, COUNT(*) AS sessions
FROM v_sessions_enriched
GROUP BY 1, 2, 3, 4
ORDER BY 1, 5 DESC;
