-- Run one statement at a time in two sessions. ERROR 40P01 is intentional.
-- SESSION A
BEGIN;
UPDATE accounts SET balance = balance - 1 WHERE id = 1;

-- SESSION B
BEGIN;
UPDATE accounts SET balance = balance - 1 WHERE id = 2;

-- SESSION A: now waits for B.
UPDATE accounts SET balance = balance + 1 WHERE id = 2;

-- SESSION B: creates the cycle; PostgreSQL aborts one transaction with deadlock detected.
UPDATE accounts SET balance = balance + 1 WHERE id = 1;

-- In the aborted session run ROLLBACK; in the surviving session run COMMIT.
-- Prevention: all callers should lock/update accounts in the same id order.

