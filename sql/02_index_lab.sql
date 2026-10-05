\set ON_ERROR_STOP on
\timing on

-- Reset: compare from an index-free baseline.
DROP INDEX IF EXISTS idx_orders_customer_id;
DROP INDEX IF EXISTS idx_orders_status_ordered_at;
ANALYZE orders;

-- Baseline: expect Seq Scan. Record actual time, estimated cost/rows and Buffers.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE customer_id = 4242;

CREATE INDEX idx_orders_customer_id ON orders (customer_id);
ANALYZE orders;

-- Expect Bitmap/Index Scan and far fewer shared buffers than the baseline.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE customer_id = 4242;

-- Low-selectivity predicate: one quarter of the table. A Seq Scan can be cheaper.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'paid';

-- Equality on status followed by a range/order on ordered_at matches this column order.
CREATE INDEX idx_orders_status_ordered_at ON orders (status, ordered_at);
ANALYZE orders;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, status, ordered_at
FROM orders
WHERE status = 'paid'
  AND ordered_at >= timestamptz '2024-01-03 00:00:00+00'
  AND ordered_at <  timestamptz '2024-01-03 01:00:00+00'
ORDER BY ordered_at;

-- The leading column is absent; this index is usually not useful for this predicate.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE ordered_at >= timestamptz '2024-01-03 00:00:00+00'
  AND ordered_at <  timestamptz '2024-01-03 01:00:00+00';

SELECT attname, n_distinct, most_common_vals
FROM pg_stats
WHERE schemaname = 'public' AND tablename = 'orders'
  AND attname IN ('customer_id', 'status');

