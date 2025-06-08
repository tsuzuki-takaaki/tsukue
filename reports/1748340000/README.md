[ISUCON公開パフォーマンスチューニング！fujiwara氏&そーだい氏ログ取得〜N+1まで全部見せ](https://youtu.be/YI9mGDRhKrM)

## 前提

- ※ 後から気づいたのだがisucon14の練習をする場合いくつか変更をする必要がある
  - See <https://zenn.dev/meihei/scraps/61a844ac783d19>
  - 証明書が切れている
  - 静的ファイルのチェックに失敗するので、--skip-static-sanity-checkをつける

## メトリクス

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
- performance_schemaもベンチマークを走らせるごとに溜まっていくため、都度更新をした方が良い
  - schemaファイルに書いてinit.shで毎度更新されるようにすると良さそう
  - <https://dev.mysql.com/doc/refman/8.0/ja/sys-ps-truncate-all-tables.html>

```sql
CALL sys.ps_truncate_all_tables(FALSE);
```

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

これで遅い「クエリ」と遅い「ページ」がわかる

- クエリだけを見て改善を図る
- ページを見て改善を図る
  - そのページで発行されているクエリを順繰りに見ていく

の2パターンあるが大抵の場合ページから行った方が良い

## PATCH

### 1. /api/chair/notificationの改善(indexの話)

まず目につくのが`SELECT * FROM rides WHERE chair_id = ? ORDER BY updated_at DESC LIMIT 1`

- schemaを見た感じ、indexは作成されていなさそう
  - かつ、slowクエリーを見たときに5番目にボトルネックになっているものだった
  - `ORDER BY created_at`との組み合わせのやつも2つくらい入ってた
    - どっちで複合indexを作成するかは、発行数とか見ると良さそう
- **愚か者は、愚直にchair_idでindexを作成するが、実際にはchair_idで探した後に`updated_at`の`ORDER BY`で探しているため複合indexにする必要がある**
  - **ORDER BYに関しては、asc, descの指定もする**
- **現時点でWHEREに対するindexの感覚はもてているが、ORDER BYに対する感覚は全く持てていないよね**
- isucon14の本番では、alpをP99で見ていたこともあってこのindexを貼れていない
  - <https://github.com/tsuzuki-takaaki/isucon14-final/blob/main/webapp/sql/1-schema.sql#L83C1-L98C25>

このindexだけでSUMが100秒ぐらい縮んだ

before

```log
+-------+-----+-------+-----+-----+-----+--------+---------------------------------------+-------+-------+---------+-------+-------+-------+-------+--------+------------+------------+-------------+------------+
| COUNT | 1XX |  2XX  | 3XX | 4XX | 5XX | METHOD |                  URI                  |  MIN  |  MAX  |   SUM   |  AVG  |  P90  |  P95  |  P99  | STDDEV | MIN(BODY)  | MAX(BODY)  |  SUM(BODY)  | AVG(BODY)  |
+-------+-----+-------+-----+-----+-----+--------+---------------------------------------+-------+-------+---------+-------+-------+-------+-------+--------+------------+------------+-------------+------------+
| 10445 | 0   | 10433 | 0   | 12  | 0   | GET    | /api/chair/notification               | 0.002 | 2.256 | 505.838 | 0.048 | 0.059 | 0.068 | 0.155 | 0.090  | 0.000      | 33.000     | 344289.000  | 32.962     |
```

after

```log
+-------+-----+-------+-----+-----+-----+--------+---------------------------------------+-------+-------+---------+-------+-------+-------+-------+--------+------------+------------+-------------+------------+
| COUNT | 1XX |  2XX  | 3XX | 4XX | 5XX | METHOD |                  URI                  |  MIN  |  MAX  |   SUM   |  AVG  |  P90  |  P95  |  P99  | STDDEV | MIN(BODY)  | MAX(BODY)  |  SUM(BODY)  | AVG(BODY)  |
+-------+-----+-------+-----+-----+-----+--------+---------------------------------------+-------+-------+---------+-------+-------+-------+-------+--------+------------+------------+-------------+------------+
| 11734 | 0   | 11732 | 0   | 2   | 0   | GET    | /api/chair/notification               | 0.002 | 1.683 | 435.748 | 0.037 | 0.047 | 0.054 | 0.080 | 0.065  | 33.000     | 33.000     | 387156.000  | 32.994     |
```

- その次に目につくのが`SELECT * FROM ride_statuses WHERE ride_id = ? AND chair_sent_at IS NULL ORDER BY created_at ASC LIMIT 1`
- で、slowクエリーで見るとこやつは2番目に遅いことがわかる
- さっきのまま愚直にいくと、`ride_id`と`created_at ASC`でindexを作成すると良さそう
  - -> `chair_sent_at IS NULL`は何処へ？
  - これはカーディナリティを見るのが正解
    - `chair_sent_at`のカーディナリティが低いのであればindexを作成したところで意味がないので
  - 結果的に`ride_id`(のASC)と`created_at`(のASC)で複合indexを作成することに

alpの結果だとSUMが100秒ぐらい縮んだ

```log
+-------+-----+-------+-----+-----+-----+--------+---------------------------------------+-------+-------+---------+-------+-------+-------+-------+--------+------------+------------+-------------+------------+
| COUNT | 1XX |  2XX  | 3XX | 4XX | 5XX | METHOD |                  URI                  |  MIN  |  MAX  |   SUM   |  AVG  |  P90  |  P95  |  P99  | STDDEV | MIN(BODY)  | MAX(BODY)  |  SUM(BODY)  | AVG(BODY)  |
+-------+-----+-------+-----+-----+-----+--------+---------------------------------------+-------+-------+---------+-------+-------+-------+-------+--------+------------+------------+-------------+------------+
| 12089 | 0   | 12086 | 0   | 3   | 0   | GET    | /api/chair/notification               | 0.002 | 1.525 | 371.164 | 0.031 | 0.043 | 0.050 | 0.071 | 0.058  | 0.000      | 33.000     | 398838.000  | 32.992     |
```

### N+1の話

若干答えから攻めてしまっている感はあるが、

```sql
SELECT OBJECT_NAME,COUNT_FETCH,COUNT_INSERT,COUNT_UPDATE,COUNT_DELETE FROM performance_schema.table_io_waits_summary_by_table
```

を見た時に、`ride_statuses`テーブルに対するCOUNT_FETCHの数が異常に多いことがわかる

↓

- N+1の可能性を疑う
- 実際にソースコードを確認すると、複数箇所で`get_latest_ride_status`が呼ばれていることがわかる
  - かつ、イテレートしている箇所で何度も呼び出されているところがある
  - <https://github.com/tsuzuki-takaaki/isucon14-final/blob/main/webapp/ruby/lib/isuride/app_handler.rb#L412C11-L419C14>
- **後々気づいたけど、showページではなくてindexページのようなページで1件取得みたいなクエリが走っていたら匂いを感じた方が良い**
  - 一気に取得できるはず？っていうことが思い浮かばないといけない
- したら、アプリケーションから`ride_statuses`を呼んでいるところ探す
  - `get_chair_stats`でiterateしている箇所で都度呼びだしが行われている
  - `# GET /api/app/rides`でもiterateしている箇所で都度呼び出しが行われていることがわかる

ここにリンクを貼る

### マッチングの話

ソースコード・メトリクスから攻めるだけでなく、ドメインから行かないといけないこともある

```log
time=14:10:51.666 level=INFO msg=最終地域情報 名前=チェアタウン ユーザー登録数=5 アクティブユーザー数=5
time=14:10:51.666 level=INFO msg=最終地域情報 名前=コシカケシティ ユーザー登録数=5 アクティブユーザー数=5
time=14:10:51.666 level=INFO msg=最終オーナー情報 名前=風座プロダクツ 売上=0 椅子数=4
time=14:10:51.666 level=INFO msg=最終オーナー情報 名前="Orbit Taxi" 売上=0 椅子数=4
time=14:10:51.666 level=INFO msg=最終オーナー情報 名前=椅子やいちば 売上=0 椅子数=4
time=14:10:51.666 level=INFO msg=最終オーナー情報 名前="PreLoved Chairs" 売上=0 椅子数=4
time=14:10:51.666 level=INFO msg=最終オーナー情報 名前=椅子のめぐりや 売上=0 椅子数=4
```

- これと、仕様を確認した時に、「マッチングができるようになる -> ユーザ数が増える -> 椅子を買うことができる -> マッチングの確率が上がる -> ...」見たいな循環をみてとることができる
- ということを正しく理解して、「マッチングを改善する」という思考にならないといけない
- <https://github.com/isucon/isucon14/blob/main/docs/ISURIDE.md#%E3%83%A9%E3%82%A4%E3%83%89%E3%81%AE%E3%83%9E%E3%83%83%E3%83%81%E3%83%B3%E3%82%B0>
  - > 初期状態では isuride-matcher というsystemdサービスがアプリケーションの GET /api/internal/matching を500msごとにポーリングすることで、ライドと椅子のマッチングを行う処理を起動しています。 以下の手順でマッチング間隔を変更することができます。
- で、この処理をしているファイルがあって
  - <https://github.com/tsuzuki-takaaki/isucon14-final/blob/main/webapp/ruby/lib/isuride/internal_handler.rb>
    - 「# MEMO: 一旦最も待たせているリクエストに適当な空いている椅子マッチさせる実装とする。おそらくもっとい>い方法があるはず…」
    - これはあからさまな運営からの改善要望なので、改善できるということがわかる
  - ここの処理は現在のpollingのinterval500msに対して、それよりもだいぶ早く終わっているかつマッチングがほとんどできてないことが問題
    - -> マッチングの可能性が上がるようにしよう
- ※ 一番重要なのは、この処理を入れることによってシステム負荷は悪化するが、加点の仕様を考慮するとマッチングが増えるためスコアは上がるということ
