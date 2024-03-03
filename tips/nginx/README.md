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

