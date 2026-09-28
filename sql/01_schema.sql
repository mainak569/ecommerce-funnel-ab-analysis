-- Schema for the Maven Fuzzy Factory data.
-- Rerunnable: drops everything first (CASCADE also drops the views that depend on the tables).

DROP TABLE IF EXISTS order_item_refunds, order_items, orders, website_pageviews, website_sessions, products CASCADE;

CREATE TABLE products (
    product_id    INTEGER PRIMARY KEY,
    created_at    TIMESTAMP NOT NULL,
    product_name  VARCHAR(100) NOT NULL
);

CREATE TABLE website_sessions (
    website_session_id  BIGINT PRIMARY KEY,
    created_at          TIMESTAMP NOT NULL,
    user_id             BIGINT NOT NULL,
    is_repeat_session   SMALLINT NOT NULL CHECK (is_repeat_session IN (0, 1)),
    utm_source          VARCHAR(50),
    utm_campaign        VARCHAR(50),
    utm_content         VARCHAR(50),
    device_type         VARCHAR(20) NOT NULL,
    http_referer        VARCHAR(100)
);

CREATE TABLE website_pageviews (
    website_pageview_id  BIGINT PRIMARY KEY,
    created_at           TIMESTAMP NOT NULL,
    website_session_id   BIGINT NOT NULL REFERENCES website_sessions (website_session_id),
    pageview_url         VARCHAR(100) NOT NULL
);

CREATE TABLE orders (
    order_id            BIGINT PRIMARY KEY,
    created_at          TIMESTAMP NOT NULL,
    website_session_id  BIGINT NOT NULL UNIQUE REFERENCES website_sessions (website_session_id),
    user_id             BIGINT NOT NULL,
    primary_product_id  INTEGER NOT NULL REFERENCES products (product_id),
    items_purchased     SMALLINT NOT NULL,
    price_usd           NUMERIC(10, 2) NOT NULL,
    cogs_usd            NUMERIC(10, 2) NOT NULL
);

CREATE TABLE order_items (
    order_item_id    BIGINT PRIMARY KEY,
    created_at       TIMESTAMP NOT NULL,
    order_id         BIGINT NOT NULL REFERENCES orders (order_id),
    product_id       INTEGER NOT NULL REFERENCES products (product_id),
    is_primary_item  SMALLINT NOT NULL CHECK (is_primary_item IN (0, 1)),
    price_usd        NUMERIC(10, 2) NOT NULL,
    cogs_usd         NUMERIC(10, 2) NOT NULL
);

CREATE TABLE order_item_refunds (
    order_item_refund_id  BIGINT PRIMARY KEY,
    created_at            TIMESTAMP NOT NULL,
    order_item_id         BIGINT NOT NULL REFERENCES order_items (order_item_id),
    order_id              BIGINT NOT NULL REFERENCES orders (order_id),
    refund_amount_usd     NUMERIC(10, 2) NOT NULL
);

-- Primary keys and UNIQUE(orders.website_session_id) already have indexes.
CREATE INDEX idx_sessions_created_at ON website_sessions (created_at);
CREATE INDEX idx_pageviews_session ON website_pageviews (website_session_id);
CREATE INDEX idx_pageviews_url ON website_pageviews (pageview_url);
CREATE INDEX idx_pageviews_created_at ON website_pageviews (created_at);
CREATE INDEX idx_orders_created_at ON orders (created_at);
CREATE INDEX idx_order_items_order ON order_items (order_id);
CREATE INDEX idx_order_items_product ON order_items (product_id);
CREATE INDEX idx_refunds_order_item ON order_item_refunds (order_item_id);
