# PostgreSQL Performance & Operations Lab

PostgreSQL の問題を自分で再現し、**観測 → 仮説 → 調査 → 原因特定 → 改善 → 再計測**するための小規模な学習環境です。`psql` はコンテナ内で実行するため、必要なのは Docker Compose だけです。意図的なエラーは各Labで明記しています。

## 0. 学習を始める

リポジトリの `postgresql-performance-lab` ディレクトリで実行します。

```sh
docker compose up -d
docker compose ps
docker compose exec postgres psql -U lab_user -d performance_lab
```

初期化と50万件の投入（ホスト側シェル）:

```sh
docker compose exec -T postgres psql -U lab_user -d performance_lab -f /lab/sql/00_schema.sql
docker compose exec -T postgres psql -U lab_user -d performance_lab -f /lab/sql/01_seed.sql
```

SQLファイルを対話的に読むときは、`psql` 内で `\i /lab/sql/08_monitoring.sql` のように実行します。複数SessionのLabは、別々のターミナルで次を起動してください。

```sh
docker compose exec postgres psql -U lab_user -d performance_lab
```

やり直す場合は `00_schema.sql` と `01_seed.sql` を再実行します。全データを捨てる場合のみ `docker compose down -v` を使います。

## Lab 1: Slow Query / Index

### Goal

Seq ScanとIndex Scanを実測で比較し、selectivity、cardinality、複合Indexの列順、Indexの代償を説明できるようにします。

### Reproduce

```sh
docker compose exec -T postgres psql -U lab_user -d performance_lab -f /lab/sql/02_index_lab.sql
```

### Observe

最初の `EXPLAIN (ANALYZE, BUFFERS)` で `Seq Scan`、`cost`、推定 `rows` と実行 `rows`、`actual time`、`shared hit/read` を記録します。Index作成後はIndex/Bitmap Scan、読んだbuffer、実行時間を比較します。キャッシュで2回目が有利になるため、複数回測り中央値を見るのが実務的です。

### Diagnose

`customer_id` は約5万種類あり絞り込みが強い一方、`status` は4種類しかなく1値で約25%を読むため、PlannerがSeq Scanを選ぶことがあります。複合Index `(status, ordered_at)` は先頭列の等価条件と後続列の範囲条件に合います。`ordered_at` 単独条件には先頭列が欠けるため使いにくい点も確認します。

### Fix

実際の検索条件に対応するIndexだけを作成します。Indexは読み取りを速くし得ますが、保存容量、INSERT/UPDATE/DELETE時の更新、VACUUM負荷が増えます。

### Verify

同じSQL・同程度のキャッシュ条件で計画、実行時間、buffer数を再計測します。Index名が出ただけでなく、総コストが下がり、読み取るpageが減ったことを確認します。

### Interview takeaway

「Indexは探索範囲を絞るが、低selectivityや大量行取得ではrandom I/Oの方が高価になり、Seq Scanが合理的。複合Indexは代表的なfilter・sortと先頭列規則から決め、書き込みコストも測る」と説明します。

## Lab 2: Lock Wait

### Goal

通常の待機を再現し、blocked sessionとblocking sessionを特定します。

### Reproduce

2つのpsql sessionで [sql/03_lock_lab.sql](sql/03_lock_lab.sql) の `SESSION A`、`SESSION B` を一文ずつ実行します。BのUPDATEが止まるのは想定動作です。観測には3つ目のsessionを使います。

### Observe

`pg_stat_activity` の `wait_event_type='Lock'`、`pg_locks.granted`、`pg_blocking_pids()` によるPID対応を見ます。

### Diagnose

Aが同じ行の変更を未確定のまま保持し、Bがその確定を待っています。DB全体が停止したのではありません。

### Fix

Aを `COMMIT` または `ROLLBACK` し、Bも終了します。実務ではblocking queryの所有者と影響を確認し、無断でPIDをterminateしません。transactionを短くし、外部API待ちを含めない設計が基本です。

### Verify

BのUPDATEが完了し、blocking一覧が0件になることを確認します。

### Interview takeaway

「待機を活動状況だけで推測せず、blocking PIDまで辿り、古いtransactionと業務影響を確認して解消する」と説明します。

## Lab 3: Deadlock

### Goal

循環待ちと単なるLock Waitの違い、DBとApplicationの役割を理解します。

### Reproduce

[sql/04_deadlock_lab.sql](sql/04_deadlock_lab.sql) を2 sessionで記載順に一文ずつ実行します。`ERROR: deadlock detected`（SQLSTATE `40P01`）は意図した結果です。

### Observe

PostgreSQLは `deadlock_timeout` 後に待機グラフのcycleを検知し、一方のtransactionをabortして他方を進めます。`docker compose logs postgres` に詳細が出ます。

### Diagnose

AはBのRow 2、BはAのRow 1を互いに待ち、誰も自力で進めない循環です。通常のLock Waitにはcycleがなく、holderが終了すれば進みます。

### Fix

全コードで同じ順序（例: account id昇順）にlockします。Applicationは `40P01` を識別し、rollback後、上限付きexponential backoffとjitterでtransaction全体をretryします。

### Verify

順序を統一して同じ操作を行い、待機はしてもdeadlockにならないことを確認します。

### Interview takeaway

DBがvictimを選ぶためエラーは起こり得ます。順序統一で頻度を下げ、retry可能・idempotentな境界を設計します。

## Lab 4: Transaction / Isolation

### Goal

snapshotの違いと、分離を強めるtrade-offを観察します。

### Reproduce

[sql/05_transaction_lab.sql](sql/05_transaction_lab.sql) の各scenarioを2 sessionで一文ずつ実行します。

### Observe

READ COMMITTEDではstatementごとに新しいsnapshotなので同じSELECTの結果が変わります。REPEATABLE READではtransaction中のsnapshotが維持されます。SERIALIZABLEでは危険な依存関係を検知し、片方が `40001` で失敗します（意図的エラー）。PostgreSQLのREAD UNCOMMITTEDはREAD COMMITTEDとして扱われ、dirty readは起きません。

### Diagnose

MVCCはtuple versionとtransaction可視性でreaderとwriterの競合を減らします。Non-repeatable readは同じ行の再読結果が変わる現象、phantom readは条件に合う行集合が変わる現象です。PostgreSQLのREPEATABLE READはphantom readも防ぎます。

### Fix

必要な整合性を満たす最弱のlevelを選びます。SERIALIZABLEは強い保証の代わりにserialization failureとretry、競合時のthroughput低下を受け入れます。

### Verify

各levelで記録した2回のSELECT結果とcommit結果を比較し、失敗時はtransaction全体をretryできる境界か確認します。

### Interview takeaway

「強い分離は無料ではない。業務invariant、競合頻度、retry設計をセットで決める」と説明します。

## Lab 5: VACUUM / Autovacuum

### Goal

MVCCが作るdead tupleを観測し、VACUUMとANALYZEの役割を分けて理解します。

### Reproduce

```sh
docker compose exec -T postgres psql -U lab_user -d performance_lab -f /lab/sql/06_vacuum_lab.sql
```

このLabは観測を安定させるため対象tableだけautovacuumを一時停止し、最後に必ず戻します。

### Observe

`pg_stat_user_tables.n_live_tup/n_dead_tup`（推定値）、maintenance時刻、実行前後を比較します。統計反映が少し遅い場合は数秒後に再SELECTします。

### Diagnose

UPDATE/DELETEされた旧versionは、古いsnapshotから見える可能性があるため即時削除できません。回収が追いつかないとtable/index bloat、I/O増加、transaction ID wraparound riskにつながります。長時間transactionはcleanup可能地点を古くします。

### Fix

通常のVACUUMは再利用可能領域を作り、ANALYZEはPlanner統計を更新します。`VACUUM ANALYZE` は両方です。autovacuumの頻度、長時間transaction、書き込み量、I/O余力を観測して調整します。`VACUUM FULL` はtableを書き直してOSへ空間を返せますが排他lockと追加diskが必要なため常用しません。

### Verify

VACUUM後のdead tuple推定、last_vacuum、query planを再確認します。ファイル容量が通常VACUUMで縮まらないのは正常です。

### Interview takeaway

VACUUMは「削除」ではなくMVCCの後片付け、freeze、空間再利用に不可欠で、遅延原因（長時間transaction等）も同時に調べます。

## Lab 6: Connections

### Goal

connectionの状態、上限、長時間transactionを観測し、poolの必要性を説明します。

### Reproduce

```sh
docker compose exec -T postgres psql -U lab_user -d performance_lab -f /lab/sql/07_connection_lab.sql
```

コメントにある複数client生成と長時間transactionも実行します。

### Observe

`SHOW max_connections` と `pg_stat_activity` のactive、idle、idle in transaction、`xact_start` を確認します。各connectionはserver processとmemory等を消費し、過多ではcontext switchingとmemory pressureが増えます。

### Diagnose

connection上限到達とquery遅延は別問題ですが、遅延でrequestが滞留してpoolが膨らむ連鎖もあります。idle in transactionはlockや古いsnapshotを保持し得ます。

### Fix

Application poolで再利用・同時実行数を制限します。複数Application/短命clientを集約するならPgBouncerを検討します。詳細は [production-considerations.md](docs/production-considerations.md) を参照してください。

### Verify

client終了後にconnection数が戻り、開いたtransactionをrollback後にlong-running一覧から消えることを確認します。

### Interview takeaway

`max_connections` を単に増やすのではなく、DBが処理できるconcurrencyにpoolを合わせ、timeoutと待ち行列も監視します。

## Lab 7: 「DBが遅い」Troubleshooting

### Goal

曖昧な症状を層別化し、証拠を保存して安全に原因へ絞り込みます。

### Reproduce

例としてSession AでLab 2のlockを保持し、Session Bを待たせます。別案として `SELECT pg_sleep(30);` を実行します。監視SQLは次です。

```sh
docker compose exec -T postgres psql -U lab_user -d performance_lab -f /lab/sql/08_monitoring.sql
```

### Observe

まず「いつから、どのquery/endpoint、全体か一部か、latencyかerrorか」を確定し、変更履歴と比較します。次にhost/containerのCPU・memory・disk I/O、connection数を見て、DB内部ではactivity、lock、長時間query/transaction、table/index統計、dead tupleを同時刻で保存します。

### Diagnose

次の順序はチェックリストではなく、分岐です。

| 症状 | 観測 | 仮説 | 確認 | 原因候補 | 対応 |
|---|---|---|---|---|---|
| 多数queryが待機 | wait_eventがLock | blockerが長時間transaction | blocking/blocked SQL | 未commit処理 | owner確認後commit/rollback、transaction短縮 |
| 特定queryだけ遅い | runtime増、I/O高 | plan/統計/data量変化 | `EXPLAIN (ANALYZE, BUFFERS)`（本番は副作用注意） | Seq Scan、誤推定 | query/index/統計を改善し再計測 |
| 全体が遅い | CPU/I/O飽和 | workload過多・bloat | OS指標、top query、dead tuple | 高負荷query、vacuum遅延 | workload抑制、query改善、maintenance調整 |
| 接続error/待ち | connection/pool待ち増 | connection storm | activity、pool metrics | pool不整合、leak | 上限とpoolを整合、leak修正 |
| replicaのみ遅延 | replay lag増 | WAL適用が追いつかない | lag、I/O、long query | 書込急増、replay阻害 | workload/replica容量/問い合わせを是正 |

### Fix

影響の小さい緩和（traffic制御、問題job停止等）と恒久対応を分けます。process kill、Index作成、設定変更はlock、WAL、I/O、rollback時間を見積もります。

### Verify

同じworkloadと時間窓でuser-visible latency/error、query time、resource、plan/buffersを比較し、副作用も確認します。時系列、仮説、否定した原因、変更、結果をincident logへ残します。

### Interview takeaway

「CPUだけを見る」のではなく、影響範囲を確定し、外部resource → activity/wait → query plan → maintenance/poolの順に証拠で枝刈りし、変更後に同条件で再計測します。

## 学習の終了と後片付け

[interview-notes.md](docs/interview-notes.md) を自分の測定値で書き足し、[study-checklist.md](docs/study-checklist.md) を埋めます。

```sh
docker compose down
# データも削除するときだけ:
docker compose down -v
```

