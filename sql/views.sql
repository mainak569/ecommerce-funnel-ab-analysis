-- Analysis views. The loader runs this after the tables are filled.

-- One row per session: traffic source, landing page, funnel progress and order outcome.
-- The funnel is linear (no session skips a step), so the deepest step reached is the furthest step.
CREATE OR REPLACE VIEW v_sessions_enriched AS
WITH pageview_flags AS (
    SELECT
        website_session_id,
        COUNT(*) AS pageviews,
        MAX(CASE WHEN pageview_url = '/products' THEN 1 ELSE 0 END) AS saw_products,
        MAX(CASE WHEN pageview_url IN ('/the-original-mr-fuzzy', '/the-forever-love-bear',
                                       '/the-birthday-sugar-panda', '/the-hudson-river-mini-bear')
                 THEN 1 ELSE 0 END) AS saw_product_page,
        MAX(CASE WHEN pageview_url = '/cart' THEN 1 ELSE 0 END) AS saw_cart,
        MAX(CASE WHEN pageview_url = '/shipping' THEN 1 ELSE 0 END) AS saw_shipping,
        MAX(CASE WHEN pageview_url IN ('/billing', '/billing-2') THEN 1 ELSE 0 END) AS saw_billing,
        MAX(CASE WHEN pageview_url = '/thank-you-for-your-order' THEN 1 ELSE 0 END) AS saw_thank_you,
        MAX(CASE WHEN pageview_url IN ('/billing', '/billing-2') THEN pageview_url END) AS billing_page
    FROM website_pageviews
    GROUP BY website_session_id
),
landing AS (
    SELECT DISTINCT ON (website_session_id)
        website_session_id,
        pageview_url AS landing_page
    FROM website_pageviews
    ORDER BY website_session_id, website_pageview_id
),
refunds AS (
    SELECT order_id, SUM(refund_amount_usd) AS refund_usd
    FROM order_item_refunds
    GROUP BY order_id
)
SELECT
    s.website_session_id,
    s.created_at,
    s.created_at::DATE AS session_date,
    DATE_TRUNC('month', s.created_at)::DATE AS session_month,
    s.user_id,
    s.is_repeat_session,
    s.utm_source,
    s.utm_campaign,
    s.utm_content,
    s.device_type,
    s.http_referer,
    CASE
        WHEN s.utm_campaign = 'nonbrand' THEN 'paid_nonbrand'
        WHEN s.utm_campaign = 'brand' THEN 'paid_brand'
        WHEN s.utm_source = 'socialbook' THEN 'paid_social'
        WHEN s.utm_source IS NULL AND s.http_referer IS NOT NULL THEN 'organic_search'
        WHEN s.utm_source IS NULL AND s.http_referer IS NULL THEN 'direct_type_in'
        ELSE 'other'
    END AS channel_group,
    l.landing_page,
    f.pageviews,
    CASE WHEN f.pageviews = 1 THEN 1 ELSE 0 END AS is_bounce,
    f.saw_products,
    f.saw_product_page,
    f.saw_cart,
    f.saw_shipping,
    f.saw_billing,
    f.saw_thank_you,
    f.billing_page,
    1 + f.saw_products + f.saw_product_page + f.saw_cart + f.saw_shipping
      + f.saw_billing + f.saw_thank_you AS furthest_step_num,
    CASE 1 + f.saw_products + f.saw_product_page + f.saw_cart + f.saw_shipping
           + f.saw_billing + f.saw_thank_you
        WHEN 1 THEN '1_landing'
        WHEN 2 THEN '2_products'
        WHEN 3 THEN '3_product_page'
        WHEN 4 THEN '4_cart'
        WHEN 5 THEN '5_shipping'
        WHEN 6 THEN '6_billing'
        WHEN 7 THEN '7_order'
    END AS furthest_step,
    o.order_id,
    CASE WHEN o.order_id IS NOT NULL THEN 1 ELSE 0 END AS has_order,
    o.primary_product_id,
    o.items_purchased,
    COALESCE(o.price_usd, 0) AS revenue_usd,
    COALESCE(o.cogs_usd, 0) AS cogs_usd,
    COALESCE(r.refund_usd, 0) AS refund_usd
FROM website_sessions s
JOIN pageview_flags f ON f.website_session_id = s.website_session_id
JOIN landing l ON l.website_session_id = s.website_session_id
LEFT JOIN orders o ON o.website_session_id = s.website_session_id
LEFT JOIN refunds r ON r.order_id = o.order_id;
