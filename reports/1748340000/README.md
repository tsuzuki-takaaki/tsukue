[ISUCON公開パフォーマンスチューニング！fujiwara氏&そーだい氏ログ取得〜N+1まで全部見せ](https://youtu.be/YI9mGDRhKrM)

- まずは何のアプリケーションが動いているのかを確認する
  - `sudo systemctl status`とかではなくて、`pstree`で確認する方が良さそう

```sh
isucon@ip-172-31-35-203:~$ pstree
systemd─┬─ModemManager───3*[{ModemManager}]
        ├─acpid
        ├─2*[agetty]
        ├─amazon-ssm-agen───7*[{amazon-ssm-agen}]
        ├─chronyd───chronyd
        ├─cron
        ├─dbus-daemon
        ├─fwupd───5*[{fwupd}]
        ├─irqbalance───{irqbalance}
        ├─isuride───8*[{isuride}]
        ├─multipathd───6*[{multipathd}]
        ├─mysqld───47*[{mysqld}]
        ├─networkd-dispat
        ├─nginx───2*[nginx]
        ├─payment_mock───4*[{payment_mock}]
        ├─polkitd───3*[{polkitd}]
        ├─rsyslogd───3*[{rsyslogd}]
        ├─sh
        ├─snapd───9*[{snapd}]
        ├─sshd─┬─sshd───sshd───bash───sudo───sudo───bash───pstree
        │      └─sshd───sshd───bash───top
        ├─systemd───(sd-pam)
        ├─systemd-journal
        ├─systemd-logind
        ├─systemd-network
        ├─systemd-resolve
        ├─systemd-udevd
        ├─udisksd───5*[{udisksd}]
        └─unattended-upgr───{unattended-upgr}
```

- alpで遅いエンドポイントを特定
  - これは割といつも通り
  - <https://github.com/tsuzuki-takaaki/isucon14-final/issues/10>
  - **パーセンタイル99じゃなくて、SUMを見た方がいい**
    - 改めて、パーセンタイル99は外れ値を除いた割と綺麗な99%のデータの「平均みたいなもの」でしかなくて、そのエンドポイントがいっぱい叩かれているかは考慮されていない
    - SUMで見れば叩かれる回数を含めてトータルの時間で見れる

sortの条件を変更

- before

```yml
matching_groups:
  - /api/app/rides/[^/]+/evaluation
  - /api/chair/rides/[^/]+/status
sort: p99
reverse: true
```

- after

```yml
matching_groups:
  - /api/app/rides/[^/]+/evaluation
  - /api/chair/rides/[^/]+/status
sort: sum
reverse: true
```

- **これもDBと同じ切り口で、「1回の処理が遅いもの」と「呼ばれすぎているもの」に分けて考える必要がある**
  - パーセンタイル99でソートするのは、1回の処理が遅いもの
  - SUMでソートするのは、「1回の処理が遅いもの」と「呼ばれすぎているもの」のどちらも含んでいる
  - -> リクエストのCountを見て切り分けは必要

で、SUMでソートした時に、`/api/chair/notification`が遅いということがわかった

```log
+-------+-----+-------+-----+-----+-----+--------+---------------------------------------+-------+-------+---------+-------+-------+-------+-------+--------+------------+------------+-------------+------------+
| COUNT | 1XX |  2XX  | 3XX | 4XX | 5XX | METHOD |                  URI                  |  MIN  |  MAX  |   SUM   |  AVG  |  P90  |  P95  |  P99  | STDDEV | MIN(BODY)  | MAX(BODY)  |  SUM(BODY)  | AVG(BODY)  |
+-------+-----+-------+-----+-----+-----+--------+---------------------------------------+-------+-------+---------+-------+-------+-------+-------+--------+------------+------------+-------------+------------+
| 10445 | 0   | 10433 | 0   | 12  | 0   | GET    | /api/chair/notification               | 0.002 | 2.256 | 505.838 | 0.048 | 0.059 | 0.068 | 0.155 | 0.090  | 0.000      | 33.000     | 344289.000  | 32.962     |
```

↓

- `/api/chair/notification`の処理を見に行く
  - <https://github.com/tsuzuki-takaaki/isucon14-final/blob/main/webapp/ruby/lib/isuride/chair_handler.rb#L105>
  - **やっぱり愚直にコードを見るのではなくて、その処理が今回の文脈においてどんな役割をしているのかを確認することが大事**
- ここでボトルネック臭いところを見つけてもすぐに直すじゃなくて、MySQLも見に行く
  - まずはschemaを見る -> indexがほとんど貼られていないことがわかる
- **その次にMySQL全体のクエリ状況を見る**
  - どのテーブルに対してどんなクエリがどれだけ走っているのか
  - -> `performance_schema.table_io_waits_summary_by_table`
    - [MySQL運用・管理［実践］入門](https://gihyo.jp/book/2024/978-4-297-14184-4) p200
    - `OBJECT`: tableの名前
    - `COUNT_FETCH`: selectの回数
    - `COUNT_INSERT`: insertされた回数
    - `COUNT_UPDATE`: updateされた回数
    - `COUNT_DELETE`: deleteされた回数
    - -> どのテーブルに対してRead/Writeがどれだけ走っているかがわかる(偏りみたいなもの)

```sql
SELECT OBJECT_NAME,COUNT_FETCH,COUNT_INSERT,COUNT_UPDATE,COUNT_DELETE FROM performance_schema.table_io_waits_summary_by_table;
```

```sql
mysql> select OBJECT_NAME,COUNT_FETCH,COUNT_INSERT,COUNT_UPDATE,COUNT_DELETE from performance_schema.table_io_waits_summary_by_table where object_name like "%ride%";
+---------------+-------------+--------------+--------------+--------------+
| OBJECT_NAME   | COUNT_FETCH | COUNT_INSERT | COUNT_UPDATE | COUNT_DELETE |
+---------------+-------------+--------------+--------------+--------------+
| rides         |     9992346 |          760 |            0 |            0 |
| ride_statuses |    20657772 |         4506 |           10 |            0 |
+---------------+-------------+--------------+--------------+--------------+
2 rows in set (0.01 sec)
```

- これだけを見ても`rides`と`ride_statuses`のI/Oが大きすぎるので、改善ポイントだということがわかる
- **また、全体として見た時にDELETEが全く走っていないこともわかる**
- **UPDATEがないテーブル -> 状態の更新がないため、キャッシュも視野に入れる**
- SQLのメトリクスを見るときは、`pt-query-digest`じゃなくて、mirakuiさんが作ったSQLを実行するのが良さそう
  - <https://blog.mirakui.com/entry/2023/11/27/152107>
  - `SUM_NO_INDEX_USED`でインデックスが使われていないクエリを特定できる

```sql
SELECT
  SCHEMA_NAME,
  -- DIGEST,
  DIGEST_TEXT,
  COUNT_STAR,
  round(SUM_TIMER_WAIT / pow(1000,4), 3) as SUM_TIMER_WAIT_SEC,
  round(MIN_TIMER_WAIT / pow(1000,4), 3) as MIN_TIMER_WAIT_SEC,
  round(AVG_TIMER_WAIT / pow(1000,4), 3) as AVG_TIMER_WAIT_SEC,
  round(MAX_TIMER_WAIT / pow(1000,4), 3) as MAX_TIMER_WAIT_SEC,
  round(SUM_LOCK_TIME / pow(1000,4), 3) as SUM_LOCK_TIME_SEC,
  round(QUANTILE_95 / pow(1000,4), 3) as P95,
  round(QUANTILE_99 / pow(1000,4), 3) as P99,
  round(QUANTILE_999 / pow(1000,4), 3) as P999,
  SUM_ERRORS,
  SUM_WARNINGS,
  SUM_ROWS_AFFECTED,
  SUM_ROWS_SENT,
  SUM_ROWS_EXAMINED,
  SUM_CREATED_TMP_DISK_TABLES,
  SUM_CREATED_TMP_TABLES,
  SUM_SELECT_FULL_JOIN,
  SUM_SELECT_FULL_RANGE_JOIN,
  SUM_SELECT_RANGE,
  SUM_SELECT_RANGE_CHECK,
  SUM_SELECT_SCAN,
  SUM_SORT_MERGE_PASSES,
  SUM_SORT_RANGE,
  SUM_SORT_ROWS,
  SUM_SORT_SCAN,
  SUM_NO_INDEX_USED,
  SUM_NO_GOOD_INDEX_USED,
  -- round(SUM_CPU_TIME / pow(1000,4), 3) as SUM_CPU_TIME_SEC,
  round(MAX_CONTROLLED_MEMORY / pow(1024,2), 3) as MAX_CONTROLLED_MEMORY_MB,
  round(MAX_TOTAL_MEMORY / pow(1024,2), 3) as MAX_TOTAL_MEMORY_MB,
  -- COUNT_SECONDARY,
  -- FIRST_SEEN,
  -- LAST_SEEN,
  QUERY_SAMPLE_TEXT,
  -- QUERY_SAMPLE_SEEN,
  round(QUERY_SAMPLE_TIMER_WAIT / pow(1000,4), 3) as QUERY_SAMPLE_TIMER_WAIT_SEC
FROM
  performance_schema.events_statements_summary_by_digest
WHERE
  `SCHEMA_NAME` != 'performance_schema'
  AND `SCHEMA_NAME` IS NOT NULL
ORDER BY
  SUM_TIMER_WAIT desc
LIMIT
  20 \G;
```

- これを毎回わざわざ叩くのではなくて、`schema`にviewを書いて、`init.sh`でDBの初期化してた
  - **migrationをdeployスクリプトに入れてもいいかも**
  - init.shを実行するようにする
