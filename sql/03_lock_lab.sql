-- Run the labelled blocks manually in two psql sessions. Do not execute this whole file.
-- SESSION A
BEGIN;
UPDATE accounts SET balance = balance - 100, updated_at = clock_timestamp() WHERE id = 1;
-- Keep this transaction open. After observing the wait, run: COMMIT;

-- SESSION B (the UPDATE waits until A commits/rolls back)
BEGIN;
UPDATE accounts SET balance = balance + 100, updated_at = clock_timestamp() WHERE id = 1;
-- After A releases the row lock this completes. Then run: COMMIT;

-- SESSION C / a third terminal: blocked PID and blocker PID.
SELECT
    blocked.pid AS blocked_pid,
    blocked.query AS blocked_query,
    blocker.pid AS blocker_pid,
    blocker.query AS blocker_query,
    now() - blocked.query_start AS wait_duration
FROM pg_stat_activity AS blocked
CROSS JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS b(blocker_pid)
JOIN pg_stat_activity AS blocker ON blocker.pid = b.blocker_pid;

-- Lock details for the two sessions.
SELECT a.pid, a.state, a.wait_event_type, a.wait_event,
       l.locktype, l.mode, l.granted, a.query
FROM pg_stat_activity AS a
JOIN pg_locks AS l ON l.pid = a.pid
WHERE a.datname = current_database()
ORDER BY a.pid, l.granted, l.locktype;

