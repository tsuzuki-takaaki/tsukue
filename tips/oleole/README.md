## オレオレ証明書を使った時に、ブラウザで証明書エラーが出る時の対処法
1. `thisisunsafe`で逃げる
1. localマシンの証明書ストアに登録する
    - リモートにある証明書を落とす
    - localマシンのkeychainにインポートする
    - `信頼`の項目を`常に信頼`にする
```sh
$ scp -i SSH_KEY USER@HOST:REMOTE_PATH LOCAL_PATH
# ex
$ scp -i ~/.ssh/isucon_secret_key.pem isucon@HOST:/etc/nginx/tls/isucon.crt ./
```

