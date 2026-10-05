#!/bin/sh
set -eu

echo "Verifying lock wait with concurrent sessions"
psql -U lab_user -d performance_lab -v ON_ERROR_STOP=1 \
  -c "BEGIN; UPDATE accounts SET balance=balance-1 WHERE id=1; SELECT pg_sleep(3); COMMIT" \
  >/tmp/lock-a.log 2>&1 &
lock_a=$!
sleep 0.5
psql -U lab_user -d performance_lab -v ON_ERROR_STOP=1 \
  -c "UPDATE accounts SET balance=balance+1 WHERE id=1" \
  >/tmp/lock-b.log 2>&1 &
lock_b=$!
sleep 0.5
blocked="$(psql -U lab_user -d performance_lab -Atc \
  "select count(*) from pg_stat_activity where cardinality(pg_blocking_pids(pid)) > 0")"
test "$blocked" -ge 1
wait "$lock_a"
wait "$lock_b"

echo "Verifying intentional deadlock detection"
psql -U lab_user -d performance_lab -v ON_ERROR_STOP=1 \
  -c "BEGIN; UPDATE accounts SET balance=balance-1 WHERE id=1; SELECT pg_sleep(1); UPDATE accounts SET balance=balance+1 WHERE id=2; COMMIT" \
  >/tmp/deadlock-a.log 2>&1 &
deadlock_a=$!
psql -U lab_user -d performance_lab -v ON_ERROR_STOP=1 \
  -c "BEGIN; UPDATE accounts SET balance=balance-1 WHERE id=2; SELECT pg_sleep(1); UPDATE accounts SET balance=balance+1 WHERE id=1; COMMIT" \
  >/tmp/deadlock-b.log 2>&1 &
deadlock_b=$!
set +e
wait "$deadlock_a"; deadlock_a_result=$?
wait "$deadlock_b"; deadlock_b_result=$?
set -e
test "$deadlock_a_result" -ne 0 -o "$deadlock_b_result" -ne 0
cat /tmp/deadlock-a.log /tmp/deadlock-b.log | grep -q "deadlock detected"

echo "Verifying REPEATABLE READ snapshot behavior"
psql -U lab_user -d performance_lab -v ON_ERROR_STOP=1 \
  -c "UPDATE accounts SET balance=10000 WHERE id=3" >/dev/null
psql -U lab_user -d performance_lab -v ON_ERROR_STOP=1 -At \
  -c "BEGIN ISOLATION LEVEL REPEATABLE READ" \
  -c "SELECT balance FROM accounts WHERE id=3" \
  -c "SELECT pg_sleep(2)" \
  -c "SELECT balance FROM accounts WHERE id=3" \
  -c "COMMIT" >/tmp/repeatable.log 2>&1 &
repeatable=$!
sleep 0.5
psql -U lab_user -d performance_lab -v ON_ERROR_STOP=1 \
  -c "UPDATE accounts SET balance=11000 WHERE id=3" >/dev/null
wait "$repeatable"
test "$(grep -c '^10000.00$' /tmp/repeatable.log)" -eq 2

echo "Concurrent-session checks passed"

