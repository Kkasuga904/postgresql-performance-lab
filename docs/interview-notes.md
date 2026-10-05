# PostgreSQL Interview Notes

各回答は **結論 → 仕組み → Labで確認した具体例 → Productionでの注意点** の順です。角括弧部分を自分の実測値に置き換えてください。

## Indexとは何ですか？ Indexを貼れば必ず高速になりますか？

1. **結論:** Indexは検索対象を絞る補助構造で、選択性の高い検索を速くし得ますが、必ず使われるわけではありません。
2. **仕組み:** B-tree等から該当tupleの場所を探します。Plannerは統計を基にSeq Scanを含む候補costを比較します。大量行を読む場合はrandom accessより連続scanが安いことがあります。
3. **Lab:** 50万行の `customer_id=4242` はIndex前のSeq Scanから作成後の[Index/Bitmap Scan]に変わり、時間が[ ] ms→[ ] ms、buffersが[ ]→[ ]でした。一方、4値しかない `status` はSeq Scanが合理的でした。
4. **Production:** workload、data分布、cacheを揃えて再計測します。Indexはdiskと書込・VACUUM費用を増やし、未使用Indexも継続観測なしに削除しません。

## Seq Scanは悪いものですか？

1. **結論:** いいえ。tableの大部分を読むときや小tableでは最適です。
2. **仕組み:** pageをまとめて順次読むため、大量のheap pageへのrandom accessより安くなり得ます。
3. **Lab:** `status='paid'` は約25%を返し、[実際のplan]でした。
4. **Production:** 「Seq Scanがある」ではなく、返却割合、頻度、I/O、推定と実測のずれ、latency影響で判断します。

## EXPLAINとEXPLAIN ANALYZEの違いは？

1. **結論:** `EXPLAIN` は推定plan、`ANALYZE` 付きは実際に実行して実測値を追加します。
2. **仕組み:** cost/estimated rowsは統計からの推定、actual time/rows/loopsは実行結果です。`BUFFERS` はpage hit/read等を示します。
3. **Lab:** 推定rowsとactual rows、Index前後のshared buffersを比較しました。
4. **Production:** 書込queryは本当に変更するためtransaction内でrollbackする等の安全策が必要です。重いqueryの実行自体が影響を与えます。

## Composite Indexの列順はどう決めますか？

1. **結論:** query patternの等価条件、範囲条件、sort、選択性を基に決めます。
2. **仕組み:** B-tree `(a,b)` は通常、先頭列aの条件から連続範囲を狭めやすく、先頭列なしのb単独には効きにくいです。
3. **Lab:** `(status, ordered_at)` はstatus等価＋時刻範囲/orderに効き、時刻単独queryでは[plan]でした。
4. **Production:** 「高cardinalityを必ず先頭」のような一律規則ではなく、代表query、include、重複Index、書込costを評価します。

## DBが突然遅くなったら何から調べますか？ Slow Queryをどう調査しますか？

1. **結論:** 影響範囲と開始時刻を確定し、変更とresource、wait、queryの順に証拠で絞ります。
2. **仕組み:** CPU/I/O/memory/connection、`pg_stat_activity`、lock/long transaction、top query、plan/buffers、統計/VACUUM、poolを時系列で関連付けます。
3. **Lab:** row lock中はblocked PIDからblockerを特定し、Index Labではplanとbuffersを前後比較しました。
4. **Production:** まず安全な緩和、次に恒久対策。同条件の再計測とuser-visible指標で確認し、killやDDLの副作用を見積もります。

## Lock Waitとは？ Deadlockとは？ どう防ぎますか？

1. **結論:** Lock Waitはholder解放で進める待機、Deadlockは循環して自力では進めない待機です。
2. **仕組み:** PostgreSQLはdeadlock cycleを検知して一方を `40P01` でabortします。
3. **Lab:** 同一row更新でBを待たせ、`pg_blocking_pids()` でAを特定しました。逆順更新では意図的にdeadlockを作りました。
4. **Production:** transactionを短くし、lock順を統一します。それでも起こり得るためrollback後にtransaction全体を上限付きでretryします。

## PostgreSQLのMVCCとは？ Transaction Isolation Levelとは？

1. **結論:** MVCCは複数tuple versionとsnapshotでconcurrencyを保ち、Isolation Levelは同時実行の見え方と許容する異常を決めます。
2. **仕組み:** READ COMMITTEDはstatement単位snapshot、REPEATABLE READはtransaction snapshot、SERIALIZABLEは直列実行相当にならない依存を検知します。PostgreSQLはdirty readを許しません。
3. **Lab:** READ COMMITTEDでは再SELECTが変化し、REPEATABLE READでは同じでした。SERIALIZABLEのwrite skewで一方が `40001` になりました。
4. **Production:** 強いlevelはserialization failureとretry、競合時throughput低下を伴います。業務invariantに必要なlevelを選びます。

## VACUUMはなぜ必要ですか？ Autovacuumが追いつかないと？ VACUUM FULLとの違いは？

1. **結論:** VACUUMはMVCCの不要versionを再利用可能にし、freezeでtransaction ID wraparoundを防ぐ必須maintenanceです。
2. **仕組み:** old snapshotから不要になったdead tupleをcleanupします。ANALYZEは別にPlanner統計を更新します。通常VACUUMはfileを縮めず、FULLはrewriteして縮めます。
3. **Lab:** 20万行UPDATE後の `n_dead_tup` が[ ]、VACUUM後[ ]、`last_vacuum` が更新されました。
4. **Production:** 遅延するとbloatとI/Oが増えます。長時間transaction、更新率、worker/I/Oを調べます。FULLは排他lockと追加spaceが必要です。

## Connection Poolはなぜ必要？ Connectionが増えすぎると？

1. **結論:** connection作成費用を償却し、DBへ流す同時実行数を制御するためです。
2. **仕組み:** connectionごとのbackendとmemory、context switchが増え、過大concurrencyはthroughputを逆に下げます。Application poolは各instance内、PgBouncerはDB前で横断的に集約します。
3. **Lab:** `pg_stat_activity` でactive/idle/idle in transactionと長時間transactionを観測しました。
4. **Production:** instance数×pool sizeを計算し、取得timeout、pool待ち、管理接続枠を設計します。上限を増やすだけでは直しません。

## Read Replicaで解決できる問題・できない問題は？

1. **結論:** read負荷分散と可用性候補にはなりますが、primary write、悪いquery、lockを自動解決しません。
2. **仕組み:** WAL replayにはlagがあり、非同期なら古い結果やfailover時data lossの可能性があります。
3. **Lab:** 単一nodeなので構築せず、WAL/replicationのfailure modeを資料で整理しました。
4. **Production:** read-after-write要件、lag、replica queryによるreplay競合、routing、promotion/fencingを設計します。

## BackupとReplicationの違いは？ RPO/RTOとは？

1. **結論:** Backupは過去の復旧点、Replicationは現在に近いcopyです。RPOは許容data loss、RTOは復旧許容時間です。
2. **仕組み:** replicaは誤操作も複製します。base backup＋連続WALでPITR、logical dumpはobject単位restoreや移行に向きます。
3. **Lab:** `pg_dump/pg_restore` 手順とrestore後の行数確認を用意しました。
4. **Production:** retentionだけでなく、暗号鍵、WAL連続性、別failure domain、定期restoreと実測RTOを管理します。

## Backupが毎日成功していればDRは成立しますか？

1. **結論:** いいえ。restore可能性と目標時間内のservice復旧を試験して初めて根拠になります。
2. **仕組み:** artifactがあっても破損、鍵/権限不足、version不整合、WAL欠落、手順不備で復旧できません。
3. **Lab:** restore先databaseを作り、object/dataを戻して件数確認するところまでを手順化しました。
4. **Production:** 定期DR exerciseでapplication smoke test、routing、担当連絡、RPO/RTOを計測し、改善を追跡します。

## PostgreSQLをProduction運用するなら何を監視しますか？

1. **結論:** user impact、resource、database wait/work、maintenance、resilienceを階層で監視します。
2. **仕組み:** latency/error/throughputからCPU・I/O・capacity、query/wait/lock/connection、dead tuple/XID、WAL/replication/backupへ掘ります。
3. **Lab:** `08_monitoring.sql` でactivity、long query/transaction、blocker、table/index統計を確認しました。
4. **Production:** baselineと変更履歴を残し、alertは行動可能な症状と枯渇予測へ結び付け、restore test ageも監視します。

## 追加質問: 実行計画の推定rowsが実測と大きく違うときは？

1. **結論:** 統計の古さ、列相関、分布の偏り、式を疑います。
2. **仕組み:** 誤推定はjoin順序・scan方式・memory見積りを誤らせます。
3. **Lab:** `pg_stats` の `n_distinct/most_common_vals` とEXPLAINのestimated/actual rowsを比較しました。
4. **Production:** ANALYZE、statistics target、extended statistics、query/index改善を候補にし、闇雲なPlanner設定無効化は避けます。

