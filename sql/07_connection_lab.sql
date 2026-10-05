-- Server limit and current usage.
SHOW max_connections;
SELECT count(*) AS total_connections,
       count(*) FILTER (WHERE state = 'active') AS active,
       count(*) FILTER (WHERE state = 'idle') AS idle,
       count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_transaction
FROM pg_stat_activity;

-- Keep a transaction open in SESSION A, then inspect it from SESSION B.
-- SESSION A: BEGIN; SELECT * FROM accounts WHERE id = 1;
SELECT pid, usename, application_name, client_addr, state,
       now() - xact_start AS transaction_age, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start;
-- SESSION A cleanup: ROLLBACK;

-- From a shell, create five idle clients for 30 seconds:
-- docker compose exec -T postgres sh -c 'for i in 1 2 3 4 5; do psql -U lab_user -d performance_lab -c "select pg_sleep(30)" & done; wait'

