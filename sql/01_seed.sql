\set ON_ERROR_STOP on
\timing on

TRUNCATE accounts, orders RESTART IDENTITY;

INSERT INTO accounts (owner_name, balance, status)
SELECT 'owner-' || g, 10000.00, 'active'
FROM generate_series(1, 10) AS g;

-- 500,000 deterministic rows. customer_id has high cardinality; status has low selectivity.
INSERT INTO orders (customer_id, status, total_amount, ordered_at, note)
SELECT
    1 + (g % 50000),
    (ARRAY['pending', 'paid', 'shipped', 'cancelled'])[1 + (g % 4)],
    (10 + (g % 50000))::numeric / 10,
    timestamptz '2024-01-01 00:00:00+00' + (g || ' seconds')::interval,
    repeat(md5(g::text), 2)
FROM generate_series(1, 500000) AS g;

ANALYZE accounts;
ANALYZE orders;

SELECT count(*) AS seeded_orders FROM orders;

