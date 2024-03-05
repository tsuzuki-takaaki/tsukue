## main.worker_processes
- ワーカプロセス数
- CPUのコア数と同じが最適解っぽい
- See `/proc/cpuinfo`

## main.worker_rlimit_nofile
- ワーカプロセスがオープン可能なファイルディスクリプタの上限
- `worker_connections`に指定してる値の大体3倍ぐらいが無難(らしい)

## main.events.worker_connections
- 1ワーカプロセスが処理するコネクションの上限
    - clientとのコネクションだけではなくて、appstream serverなどとのコネクションも含まれる
- `worker_rlimit_nofile`が天井になる
- とりあえずデフォルトでいい
    - [ ] metrics系ができる様になって計測してから決める
    - エラーログを見て決めるのが:yosa:

## keepalive_timeout
- keepaliveを切断する時間
- default: 75s

## keepalive_reqeusts
- 上限を超えるrequestを(通算で)したら、keepaliveを切断する

## sendfile
- [x] `on`でいい
- ファイルの読み込み(Read)・レスポンスの送信(Write)に`sendfile()`システムコールが使われる
- > sendfile() copies data between one file descriptor and another. Because this copying is done within the kernel, sendfile() is more efficient than the combination of read(2) and write(2)
- 空間のスイッチが必要なくなる

## tcp_nopush
- [x] `on`でいい
- 最も大きなパケットサイズで、レスポンスヘッダとファイルの内容を送信でき、送信するパケット数を最小化できる

## open_file_cache
- オープンしたファイルの情報を一定期間キャッシュする
- `open_file_cache max=100 inactive=20s;`とか

## gzip
- [x] `on`でいい
- レスポンスボディを動的に圧縮する

