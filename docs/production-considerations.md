# Production Considerations

このLabの単一containerは仕組みを学ぶ環境であり、本番構成ではありません。本番では可用性、security、capacity、変更管理、監視、復旧訓練をservice要件から設計します。

## ConnectionsとPool

PostgreSQLは基本的にconnectionごとにbackend processを持つため、connection増加はmemory、process scheduling、context switchを増やします。`max_connections` は処理能力そのものではなく安全上限です。高くする前に、DBが許容できる同時query数、各queryのmemory、maintenance用・管理用予約、pool待ち時間をcapacity testで決めます。

- Application pool: 各application instance内でconnectionを再利用し、transaction境界やsession状態を扱いやすい。一方、instance数 × pool sizeがDB上限を超え得る。
- PgBouncer: DBの前で多数clientを少数server connectionへ集約する。短命connectionや多数instanceに有効。transaction poolingではsession変数、prepared statement、一時table等との互換性を確認する。

poolはDBを高速化する魔法ではなくconcurrencyを制御する待ち行列です。取得timeout、query/statement timeout、idle-in-transaction timeout、leak、active/idle/pending、saturationを監視します。

## VACUUM / Autovacuum

MVCCではUPDATEが新しいtuple versionを作り、DELETE/UPDATEの旧versionは全snapshotから不要になって初めて再利用できます。通常VACUUMはdead tupleを再利用可能にし、visibility map更新とtransaction ID freezeも担いますが、原則table fileをOSへ返しません。ANALYZEは値分布をsampleしてPlanner統計を更新します。

Autovacuumが追いつかない兆候はdead tuple増加、table/index size増大、scan I/O増加、古い `relfrozenxid`、workerの長時間稼働です。原因には高い更新率、閾値不適合、I/O不足、長時間transaction、replication slot等があります。table単位設定を検討し、停止を恒久対策にしません。`VACUUM FULL` はrewriteで縮小できますが排他lock、追加disk、WALを伴うためmaintenanceとして計画します。

## Backup / Restore / Replication

### Logical backup: pg_dump / pg_restore

`pg_dump` は一貫したsnapshotからdatabase object/dataをlogicalに出力します。custom formatなら `pg_restore` でobject選択やparallel restoreが可能です。version移行や部分restoreに向きますが、大規模DBでは時間がかかり、cluster-wide role/tablespaceは別途扱います。`pg_dump` 単体は連続PITRを提供しません。

例（Lab外の学習用。password管理、保存先、暗号化は本番設計が必要）:

```sh
docker compose exec -T postgres pg_dump -U lab_user -d performance_lab -Fc > performance_lab.dump
docker compose exec -T postgres createdb -U lab_user restore_test
docker compose exec -T postgres pg_restore -U lab_user -d restore_test --clean --if-exists < performance_lab.dump
docker compose exec -T postgres psql -U lab_user -d restore_test -c "select count(*) from orders"
```

### Physical backup、WAL、PITR

Physical backupはdata fileをcluster単位で取得し、同じmajor version/architecture等の制約を受けますが、大規模環境を高速に復旧しやすい方式です。`pg_basebackup` 等のbase backupと、変更記録であるWAL（Write-Ahead Log）の継続archiveを組み合わせ、指定時刻/LSNまでreplayするのがPITRです。WAL archiveの欠落は復旧鎖を切ります。

### Streaming replication / Read Replica / Failover

Primaryが生成したWALをstandbyへ送りreplayします。非同期replicationではcommit済みでもstandby未到達分をfailover時に失う可能性があり、同期replicationはRPOを改善する代わりにwrite latencyと可用性のtrade-offがあります。Read Replicaはread分散、reporting、DR候補に使えますが、primaryのwrite bottleneck、悪いquery、lock問題を自動解決しません。replication lagによりread-after-writeも保証されません。

Failoverはstandby昇格だけではなく、正しいprimary選出、split-brain防止、client routing、旧primary隔離、復帰後の再構築が必要です。Replicationは誤DELETEやcorruptionも複製するためbackupの代替ではありません。

## RPO / RTOとRestore検証

- RPO: 許容できるdata lossの時点差。例: RPO 5分なら最大5分分のcommit損失を許容。
- RTO: service復旧までの許容時間。download、restore、WAL replay、検証、routing変更も含む。

「backup jobが成功」はartifactを作れたという観測にすぎません。restore可能性には、checksum/完全性、暗号鍵、権限、依存object、version互換性、WAL連続性、手順、担当者、所要時間、復旧後の業務整合性が含まれます。隔離環境への定期restore、行数/制約/application smoke test、実測RTO、証跡を残します。

## RDS for Oracle経験との接続

共通するのは、RPO/RTOから方式を選ぶこと、backup retentionと暗号鍵を守ること、replicaとbackupを混同しないこと、restore/failoverを訓練して初めてDR能力になることです。監視、変更管理、容量計画、runbook、復旧後検証も転用できます。

主な差分は用語と内部機構です。PostgreSQLはWAL、MVCC tuple、VACUUM/autovacuum、physical/logical backup、streaming replicationを中心に理解します。OracleのUNDO、REDO、RMAN、Data Guard等と目的が似る部分はあっても、運用command、整合性条件、version制約、failure modeを一対一対応と決めつけず、PostgreSQLのdocumentと実測で確認します。Managed serviceではproviderが一部を自動化しても、RPO/RTOとrestore testの責任は消えません。

## 最低限の本番監視

- User view: availability、error rate、latency、throughput
- Resource: CPU、memory、disk capacity/latency/IOPS、network
- Database: connections/pool待ち、query latency/top query、wait events、lock、long transaction
- Storage health: dead tuples、autovacuum/analyze、table/index growth、transaction ID age
- Resilience: WAL/archive failure、replication lag、backup age、restore test age

alertは単一の瞬間値より、user impactまたは枯渇予測に結び付けます。baselineと変更履歴がなければ「異常」を判断しにくいため、時系列dashboardとdeployment annotationを用意します。

