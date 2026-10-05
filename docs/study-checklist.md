# Study Checklist

チェックは、SQLを実行しただけでなく、自分の言葉と測定値で説明できたら付けます。

- [ ] Indexなしの実行計画（Seq Scan、cost、actual、rows、buffers）を説明できる
- [ ] Index追加後の実行計画と時間・bufferの変化を説明できる
- [ ] Indexが使われない合理的なケースを説明できる
- [ ] SelectivityとCardinalityを具体例で説明できる
- [ ] Composite Indexの列順をquery patternから説明できる
- [ ] Lock Waitを2 sessionで再現できる
- [ ] `pg_stat_activity`、`pg_locks`、`pg_blocking_pids()` でBlocking Sessionを特定できる
- [ ] Deadlockを再現し、意図した `40P01` と本当の不具合を区別できる
- [ ] Lock WaitとDeadlockの差、lock順序統一、retryを説明できる
- [ ] READ COMMITTEDとREPEATABLE READの見え方の差を実演できる
- [ ] SERIALIZABLEの `40001` を再現し、transaction全体のretryを説明できる
- [ ] PostgreSQLのMVCCをtuple versionとsnapshotで説明できる
- [ ] Dirty Read、Non-repeatable Read、Phantom Readを説明できる
- [ ] VACUUMが必要な理由を説明できる
- [ ] Dead Tupleを確認し、VACUUM後の変化を説明できる
- [ ] Autovacuum遅延、長時間transaction、bloatの関係を説明できる
- [ ] VACUUM、ANALYZE、VACUUM FULLの違いを説明できる
- [ ] active / idle / idle in transactionを区別できる
- [ ] Connection Poolの目的とApplication pool / PgBouncerの差を説明できる
- [ ] DBが遅い場合の調査順序を、症状から分岐させて説明できる
- [ ] Monitoring SQLを見ずに、最初に必要な3つを選べる
- [ ] Logical / Physical Backup、Replication、PITRの違いを説明できる
- [ ] WALの役割を説明できる
- [ ] RPO / RTOを具体的な数値例で説明できる
- [ ] 「Backup成功」と「Restore/DR成立」が異なる理由を説明できる
- [ ] Oracle RDS経験からPostgreSQLへ転用できる考え方と差分を説明できる

## 自分の実測メモ

| Lab | Baseline | Change | Result | 次に調べること |
|---|---|---|---|---|
| Index |  |  |  |  |
| Lock |  |  |  |  |
| Deadlock |  |  |  |  |
| Isolation |  |  |  |  |
| Vacuum |  |  |  |  |
| Connections |  |  |  |  |

