-- Use two sessions and reset account 3 before each scenario:
UPDATE accounts SET balance = 10000 WHERE id = 3;

-- READ COMMITTED / SESSION A: each statement receives a new snapshot.
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT balance FROM accounts WHERE id = 3;
-- SESSION B: UPDATE accounts SET balance = 11000 WHERE id = 3;
-- SESSION A: SELECT again => 11000 (non-repeatable read), then ROLLBACK.

-- REPEATABLE READ / SESSION A: one transaction snapshot.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT balance FROM accounts WHERE id = 3;
-- SESSION B: UPDATE accounts SET balance = 12000 WHERE id = 3;
-- SESSION A: SELECT again => still the first value, then COMMIT.

-- ROLLBACK demonstration.
BEGIN;
UPDATE accounts SET balance = 9999 WHERE id = 3;
ROLLBACK;
SELECT balance FROM accounts WHERE id = 3;

-- SERIALIZABLE write-skew demonstration. Reset first:
UPDATE accounts SET status = 'active' WHERE id IN (4, 5);
-- SESSION A: BEGIN ISOLATION LEVEL SERIALIZABLE;
-- SESSION B: BEGIN ISOLATION LEVEL SERIALIZABLE;
-- BOTH: SELECT count(*) FROM accounts WHERE id IN (4,5) AND status='active';
-- A: UPDATE accounts SET status='suspended' WHERE id=4;
-- B: UPDATE accounts SET status='suspended' WHERE id=5;
-- Commit both. One receives intentional ERROR 40001 serialization_failure.
-- The application must roll back and retry the entire failed transaction.

