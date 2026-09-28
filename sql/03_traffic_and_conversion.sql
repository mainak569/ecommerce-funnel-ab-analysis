-- Traffic and conversion analysis. Built on v_sessions_enriched (see sql/views.sql).
-- Monthly queries use full months only: April 2012 to February 2015
-- (March 2012 starts on the 19th and March 2015 ends on the 19th).

-- 1. Sessions, orders, conversion rate and revenue per session by channel group
SELECT
    channel_group,
    COUNT(*) AS sessions,
    SUM(has_order) AS orders,
    ROUND(100.0 * SUM(has_order) / COUNT(*), 2) AS conv_rate_pct,
    SUM(revenue_usd) AS revenue,
    ROUND(SUM(revenue_usd) / COUNT(*), 2) AS revenue_per_session,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_of_sessions_pct
FROM v_sessions_enriched
GROUP BY channel_group
ORDER BY sessions DESC;


-- 2a. The same by device
SELECT
    device_type,
    COUNT(*) AS sessions,
    SUM(has_order) AS orders,
    ROUND(100.0 * SUM(has_order) / COUNT(*), 2) AS conv_rate_pct,
    SUM(revenue_usd) AS revenue,
    ROUND(SUM(revenue_usd) / COUNT(*), 2) AS revenue_per_session
FROM v_sessions_enriched
GROUP BY device_type
ORDER BY sessions DESC;

-- 2b. Channel x device
SELECT
    channel_group,
    device_type,
    COUNT(*) AS sessions,
    SUM(has_order) AS orders,
    ROUND(100.0 * SUM(has_order) / COUNT(*), 2) AS conv_rate_pct,
    ROUND(SUM(revenue_usd) / COUNT(*), 2) AS revenue_per_session
FROM v_sessions_enriched
GROUP BY channel_group, device_type
ORDER BY channel_group, device_type;


-- 3. Monthly sessions, orders and conversion by channel, with month-over-month change.
-- paid_social only ran in some months, so MoM is only computed when the previous row
-- really is the previous calendar month.
WITH monthly AS (
    SELECT
        session_month,
        channel_group,
        COUNT(*) AS sessions,
        SUM(has_order) AS orders
    FROM v_sessions_enriched
    WHERE session_month BETWEEN '2012-04-01' AND '2015-02-01'
    GROUP BY session_month, channel_group
)
SELECT
    session_month,
    channel_group,
    sessions,
    orders,
    ROUND(100.0 * orders / sessions, 2) AS conv_rate_pct,
    CASE WHEN LAG(session_month) OVER w = session_month - INTERVAL '1 month'
         THEN ROUND(100.0 * (sessions - LAG(sessions) OVER w) / LAG(sessions) OVER w, 1)
    END AS sessions_mom_pct,
    CASE WHEN LAG(session_month) OVER w = session_month - INTERVAL '1 month'
         THEN ROUND(100.0 * (orders - LAG(orders) OVER w) / NULLIF(LAG(orders) OVER w, 0), 1)
    END AS orders_mom_pct
FROM monthly
WINDOW w AS (PARTITION BY channel_group ORDER BY session_month)
ORDER BY channel_group, session_month;


-- 4a. Year-over-year growth for the same month, total and per channel.
-- ROLLUP adds an 'all_channels' row per month; the self-join matches each month to the same month a year earlier.
WITH monthly AS (
    SELECT
        session_month,
        COALESCE(channel_group, 'all_channels') AS channel_group,
        COUNT(*) AS sessions,
        SUM(has_order) AS orders,
        SUM(revenue_usd) AS revenue
    FROM v_sessions_enriched
    WHERE session_month BETWEEN '2012-04-01' AND '2015-02-01'
    GROUP BY session_month, ROLLUP (channel_group)
)
SELECT
    cur.session_month,
    cur.channel_group,
    cur.sessions,
    prev.sessions AS sessions_last_year,
    ROUND(100.0 * (cur.sessions - prev.sessions) / prev.sessions, 1) AS sessions_yoy_pct,
    cur.orders,
    prev.orders AS orders_last_year,
    ROUND(100.0 * (cur.orders - prev.orders) / NULLIF(prev.orders, 0), 1) AS orders_yoy_pct,
    ROUND(100.0 * cur.orders / cur.sessions, 2) AS conv_rate_pct,
    ROUND(100.0 * prev.orders / prev.sessions, 2) AS conv_rate_last_year_pct,
    ROUND(100.0 * (cur.revenue - prev.revenue) / NULLIF(prev.revenue, 0), 1) AS revenue_yoy_pct
FROM monthly cur
JOIN monthly prev
  ON prev.channel_group = cur.channel_group
 AND prev.session_month = cur.session_month - INTERVAL '1 year'
ORDER BY cur.channel_group, cur.session_month;

-- 4b. Year-over-year on comparable periods (April to February, the full months available in every year)
WITH periods AS (
    SELECT
        CASE
            WHEN session_month BETWEEN '2012-04-01' AND '2013-02-01' THEN 'Apr12-Feb13'
            WHEN session_month BETWEEN '2013-04-01' AND '2014-02-01' THEN 'Apr13-Feb14'
            WHEN session_month BETWEEN '2014-04-01' AND '2015-02-01' THEN 'Apr14-Feb15'
        END AS period,
        has_order,
        revenue_usd
    FROM v_sessions_enriched
),
totals AS (
    SELECT period, COUNT(*) AS sessions, SUM(has_order) AS orders, SUM(revenue_usd) AS revenue
    FROM periods
    WHERE period IS NOT NULL
    GROUP BY period
)
SELECT
    period,
    sessions,
    orders,
    revenue,
    ROUND(100.0 * orders / sessions, 2) AS conv_rate_pct,
    ROUND(revenue / sessions, 2) AS revenue_per_session,
    ROUND(100.0 * (sessions - LAG(sessions) OVER (ORDER BY period)) / LAG(sessions) OVER (ORDER BY period), 1) AS sessions_yoy_pct,
    ROUND(100.0 * (orders - LAG(orders) OVER (ORDER BY period)) / LAG(orders) OVER (ORDER BY period), 1) AS orders_yoy_pct,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY period)) / LAG(revenue) OVER (ORDER BY period), 1) AS revenue_yoy_pct
FROM totals
ORDER BY period;


-- 5a. Channel mix over time: each channel's share of the month's sessions
SELECT
    session_month,
    channel_group,
    COUNT(*) AS sessions,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY session_month), 1) AS share_of_month_pct
FROM v_sessions_enriched
WHERE session_month BETWEEN '2012-04-01' AND '2015-02-01'
GROUP BY session_month, channel_group
ORDER BY session_month, sessions DESC;

-- 5b. Share by year and the change in share (percentage points) between the first and last comparable period
WITH shares AS (
    SELECT
        CASE
            WHEN session_month BETWEEN '2012-04-01' AND '2013-02-01' THEN 'Apr12-Feb13'
            WHEN session_month BETWEEN '2013-04-01' AND '2014-02-01' THEN 'Apr13-Feb14'
            WHEN session_month BETWEEN '2014-04-01' AND '2015-02-01' THEN 'Apr14-Feb15'
        END AS period,
        channel_group,
        COUNT(*) AS sessions
    FROM v_sessions_enriched
    GROUP BY 1, 2
),
pct AS (
    SELECT
        period,
        channel_group,
        sessions,
        100.0 * sessions / SUM(sessions) OVER (PARTITION BY period) AS share_pct
    FROM shares
    WHERE period IS NOT NULL
)
SELECT
    channel_group,
    ROUND(MAX(share_pct) FILTER (WHERE period = 'Apr12-Feb13'), 1) AS share_y1_pct,
    ROUND(MAX(share_pct) FILTER (WHERE period = 'Apr13-Feb14'), 1) AS share_y2_pct,
    ROUND(MAX(share_pct) FILTER (WHERE period = 'Apr14-Feb15'), 1) AS share_y3_pct,
    ROUND(COALESCE(MAX(share_pct) FILTER (WHERE period = 'Apr14-Feb15'), 0)
        - COALESCE(MAX(share_pct) FILTER (WHERE period = 'Apr12-Feb13'), 0), 1) AS change_pp
FROM pct
GROUP BY channel_group
ORDER BY change_pp DESC;


-- 6a. Repeat vs new sessions
SELECT
    CASE WHEN is_repeat_session = 1 THEN 'repeat' ELSE 'new' END AS session_type,
    COUNT(*) AS sessions,
    SUM(has_order) AS orders,
    ROUND(100.0 * SUM(has_order) / COUNT(*), 2) AS conv_rate_pct,
    ROUND(SUM(revenue_usd) / COUNT(*), 2) AS revenue_per_session
FROM v_sessions_enriched
GROUP BY 1
ORDER BY 1;

-- 6b. Which channels repeat visitors come back through
SELECT
    channel_group,
    COUNT(*) FILTER (WHERE is_repeat_session = 0) AS new_sessions,
    COUNT(*) FILTER (WHERE is_repeat_session = 1) AS repeat_sessions,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_repeat_session = 1) / COUNT(*), 1) AS repeat_share_pct,
    ROUND(100.0 * SUM(has_order) FILTER (WHERE is_repeat_session = 1)
        / NULLIF(COUNT(*) FILTER (WHERE is_repeat_session = 1), 0), 2) AS repeat_conv_rate_pct
FROM v_sessions_enriched
GROUP BY channel_group
ORDER BY repeat_sessions DESC;
