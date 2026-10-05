\set ON_ERROR_STOP on
\timing on

-- Autovacuum is temporarily disabled only to make dead tuples observable deterministically.
ALTER TABLE orders SET (autovacuum_enabled = false);
SELECT pg_stat_reset_single_table_counters('public.orders'::regclass);

UPDATE orders SET note = note || '-changed' WHERE id <= 200000;
ANALYZE orders;

SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum
FROM pg_stat_user_tables WHERE relname = 'orders';

VACUUM (ANALYZE, VERBOSE) orders;

SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum
FROM pg_stat_user_tables WHERE relname = 'orders';

-- Restore normal behavior. Run more UPDATEs and observe last_autovacuum later.
ALTER TABLE orders RESET (autovacuum_enabled);
SELECT reloptions FROM pg_class WHERE oid = 'public.orders'::regclass;

