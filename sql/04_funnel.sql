-- Funnel and landing page analysis.

-- 7. Funnel from the raw pageviews: per-session step flags with MAX(CASE WHEN ...),
-- then counts per step and step-to-step click-through rates.
WITH session_flags AS (
    SELECT
        website_session_id,
        MAX(CASE WHEN pageview_url = '/products' THEN 1 ELSE 0 END) AS to_products,
        MAX(CASE WHEN pageview_url IN ('/the-original-mr-fuzzy', '/the-forever-love-bear',
                                       '/the-birthday-sugar-panda', '/the-hudson-river-mini-bear')
                 THEN 1 ELSE 0 END) AS to_product_page,
        MAX(CASE WHEN pageview_url = '/cart' THEN 1 ELSE 0 END) AS to_cart,
        MAX(CASE WHEN pageview_url = '/shipping' THEN 1 ELSE 0 END) AS to_shipping,
        MAX(CASE WHEN pageview_url IN ('/billing', '/billing-2') THEN 1 ELSE 0 END) AS to_billing,
        MAX(CASE WHEN pageview_url = '/thank-you-for-your-order' THEN 1 ELSE 0 END) AS to_order
    FROM website_pageviews
    GROUP BY website_session_id
),
step_counts AS (
    SELECT 1 AS step_num, 'landing' AS step, COUNT(*) AS sessions FROM session_flags
    UNION ALL SELECT 2, 'products', SUM(to_products) FROM session_flags
    UNION ALL SELECT 3, 'product_page', SUM(to_product_page) FROM session_flags
    UNION ALL SELECT 4, 'cart', SUM(to_cart) FROM session_flags
    UNION ALL SELECT 5, 'shipping', SUM(to_shipping) FROM session_flags
    UNION ALL SELECT 6, 'billing', SUM(to_billing) FROM session_flags
    UNION ALL SELECT 7, 'order', SUM(to_order) FROM session_flags
)
SELECT
    step_num,
    step,
    sessions,
    ROUND(100.0 * sessions / LAG(sessions) OVER (ORDER BY step_num), 2) AS step_ctr_pct,
    ROUND(100.0 - 100.0 * sessions / LAG(sessions) OVER (ORDER BY step_num), 2) AS step_drop_pct,
    ROUND(100.0 * sessions / FIRST_VALUE(sessions) OVER (ORDER BY step_num), 2) AS pct_of_sessions
FROM step_counts
ORDER BY step_num;


-- 8a. Funnel by device: click-through rate of each step from the one before it
SELECT
    device_type,
    COUNT(*) AS sessions,
    ROUND(100.0 * SUM(saw_products) / COUNT(*), 1) AS landing_to_products,
    ROUND(100.0 * SUM(saw_product_page) / SUM(saw_products), 1) AS products_to_product_page,
    ROUND(100.0 * SUM(saw_cart) / SUM(saw_product_page), 1) AS product_page_to_cart,
    ROUND(100.0 * SUM(saw_shipping) / SUM(saw_cart), 1) AS cart_to_shipping,
    ROUND(100.0 * SUM(saw_billing) / SUM(saw_shipping), 1) AS shipping_to_billing,
    ROUND(100.0 * SUM(saw_thank_you) / SUM(saw_billing), 1) AS billing_to_order,
    ROUND(100.0 * SUM(saw_thank_you) / COUNT(*), 2) AS overall_conv_pct
FROM v_sessions_enriched
GROUP BY device_type
ORDER BY device_type;

-- 8b. Funnel by channel group
SELECT
    channel_group,
    COUNT(*) AS sessions,
    ROUND(100.0 * SUM(saw_products) / COUNT(*), 1) AS landing_to_products,
    ROUND(100.0 * SUM(saw_product_page) / SUM(saw_products), 1) AS products_to_product_page,
    ROUND(100.0 * SUM(saw_cart) / SUM(saw_product_page), 1) AS product_page_to_cart,
    ROUND(100.0 * SUM(saw_shipping) / SUM(saw_cart), 1) AS cart_to_shipping,
    ROUND(100.0 * SUM(saw_billing) / SUM(saw_shipping), 1) AS shipping_to_billing,
    ROUND(100.0 * SUM(saw_thank_you) / SUM(saw_billing), 1) AS billing_to_order,
    ROUND(100.0 * SUM(saw_thank_you) / COUNT(*), 2) AS overall_conv_pct
FROM v_sessions_enriched
GROUP BY channel_group
ORDER BY sessions DESC;

-- 8c. Biggest drop-off per segment: unpivot the steps, then rank them by drop rate within each segment
WITH segment_steps AS (
    SELECT
        'device' AS segment_type,
        device_type AS segment,
        SUM(1) AS s1, SUM(saw_products) AS s2, SUM(saw_product_page) AS s3, SUM(saw_cart) AS s4,
        SUM(saw_shipping) AS s5, SUM(saw_billing) AS s6, SUM(saw_thank_you) AS s7
    FROM v_sessions_enriched
    GROUP BY device_type
    UNION ALL
    SELECT
        'channel', channel_group,
        SUM(1), SUM(saw_products), SUM(saw_product_page), SUM(saw_cart),
        SUM(saw_shipping), SUM(saw_billing), SUM(saw_thank_you)
    FROM v_sessions_enriched
    GROUP BY channel_group
),
drops AS (
    SELECT
        segment_type,
        segment,
        t.transition,
        ROUND(100.0 - 100.0 * t.next_step / t.this_step, 1) AS drop_pct
    FROM segment_steps
    CROSS JOIN LATERAL (VALUES
        ('landing -> products', s1, s2),
        ('products -> product_page', s2, s3),
        ('product_page -> cart', s3, s4),
        ('cart -> shipping', s4, s5),
        ('shipping -> billing', s5, s6),
        ('billing -> order', s6, s7)
    ) AS t (transition, this_step, next_step)
)
SELECT segment_type, segment, transition, drop_pct
FROM (
    SELECT drops.*, RANK() OVER (PARTITION BY segment_type, segment ORDER BY drop_pct DESC) AS drop_rank
    FROM drops
) ranked
WHERE drop_rank <= 2
ORDER BY segment_type, segment, drop_rank;


-- 9. Bounce rate by landing page (a bounce = a session with exactly one pageview)
SELECT
    landing_page,
    MIN(session_date) AS first_seen,
    MAX(session_date) AS last_seen,
    COUNT(*) AS sessions,
    SUM(is_bounce) AS bounces,
    ROUND(100.0 * SUM(is_bounce) / COUNT(*), 2) AS bounce_rate_pct
FROM v_sessions_enriched
GROUP BY landing_page
ORDER BY landing_page;


-- 10a. Landing page performance, all traffic
SELECT
    landing_page,
    COUNT(*) AS sessions,
    ROUND(100.0 * SUM(is_bounce) / COUNT(*), 2) AS bounce_rate_pct,
    ROUND(100.0 * SUM(has_order) / COUNT(*), 2) AS conv_rate_pct,
    ROUND(SUM(revenue_usd) / COUNT(*), 2) AS revenue_per_session
FROM v_sessions_enriched
GROUP BY landing_page
ORDER BY landing_page;

-- 10b. The same within paid nonbrand search only, split by device.
-- /home serves brand, organic and direct visitors who already know the store, so comparing it
-- to the landers across all traffic mixes up page quality with traffic quality.
SELECT
    landing_page,
    device_type,
    COUNT(*) AS sessions,
    ROUND(100.0 * SUM(is_bounce) / COUNT(*), 2) AS bounce_rate_pct,
    ROUND(100.0 * SUM(has_order) / COUNT(*), 2) AS conv_rate_pct,
    ROUND(SUM(revenue_usd) / COUNT(*), 2) AS revenue_per_session
FROM v_sessions_enriched
WHERE channel_group = 'paid_nonbrand'
GROUP BY landing_page, device_type
ORDER BY device_type, landing_page;
