-- Current non-idle queries: what is executing or waiting now?
SELECT pid, usename, state, wait_event_type, wait_event,
       now() - query_start AS runtime, query
FROM pg_stat_activity
WHERE datname = current_database() AND state <> 'idle' AND pid <> pg_backend_pid()
ORDER BY query_start;

-- Long-running queries: statements active for more than five seconds.
SELECT pid, now() - query_start AS runtime, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE state = 'active' AND query_start < now() - interval '5 seconds'
ORDER BY query_start;

-- Connection count: total and state breakdown.
SELECT state, count(*) FROM pg_stat_activity GROUP BY state ORDER BY state;

-- Idle connections: sessions consuming a backend but doing no work.
SELECT pid, usename, application_name, client_addr, now() - state_change AS idle_for
FROM pg_stat_activity WHERE state = 'idle' ORDER BY state_change;

-- Long-running transactions: old snapshots can delay tuple cleanup.
SELECT pid, state, now() - xact_start AS xact_age, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL AND xact_start < now() - interval '10 seconds'
ORDER BY xact_start;

-- Lock waits: sessions currently waiting on a lock.
SELECT pid, now() - query_start AS waiting_for, wait_event, query
FROM pg_stat_activity WHERE wait_event_type = 'Lock' ORDER BY query_start;

-- Blocking/blocked sessions: identify who must finish or be investigated first.
SELECT blocked.pid AS blocked_pid, blocked.query AS blocked_query,
       blocker.pid AS blocker_pid, blocker.query AS blocker_query,
       now() - blocked.query_start AS wait_duration
FROM pg_stat_activity AS blocked
CROSS JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS b(blocker_pid)
JOIN pg_stat_activity AS blocker ON blocker.pid = b.blocker_pid;

-- Table statistics: scans, estimated tuples and maintenance timestamps.
SELECT relname, seq_scan, idx_scan, n_live_tup, n_dead_tup,
       last_analyze, last_autoanalyze, last_vacuum, last_autovacuum
FROM pg_stat_user_tables ORDER BY relname;

-- Dead tuples: tables where cleanup pressure is highest.
SELECT relname, n_live_tup, n_dead_tup,
       round(100.0 * n_dead_tup / greatest(n_live_tup + n_dead_tup, 1), 2) AS dead_pct
FROM pg_stat_user_tables ORDER BY n_dead_tup DESC;

-- Index usage: indexes with zero scans may be new, unnecessary, or simply not observed long enough.
SELECT schemaname, relname, indexrelname, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes ORDER BY idx_scan, relname, indexrelname;

