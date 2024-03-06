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

## オレオレ認証局・オレオレ証明書を作る
- `/etc/ssl/openssl.cnf`に追記
    - この例では、架空ドメイン`tls-test-domain.local`を使う
    - `subjectAltName`を指定しなかった場合、Chromeのセキュリティに引っかかる
        - Chromeの場合、`CommonName`が非推奨で、`subjectAltName`が必須
        - https://developer.chrome.com/blog/chrome-58-deprecations?hl=ja#remove_support_for_commonname_matching_in_certificates
```cnf
[CA]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = digitalSignature, keyCertSign, cRLSign

[Server]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:*.tls-test-domain.local, DNS:tls-test-domain.local
```

※ 証明書は、`/etc/nginx/tls/`に置くことを仮定

- オレオレRoot証明書を作る
```sh
$ sudo openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /etc/nginx/tls/ca.key
$ sudo openssl req -new -key /etc/nginx/tls/ca.key -out /etc/nginx/tls/ca.csr
$ sudo openssl x509 -req -in /etc/nginx/tls/ca.csr -days 365 -signkey /etc/nginx/tls/ca.key -out /etc/nginx/tls/ca.crt -extfile /etc/ssl/openssl.cnf -extensions CA
```

- オレオレサーバ証明書を作る
```sh
$ sudo openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out /etc/nginx/tls/server.key
$ sudo openssl req -new -key /etc/nginx/tls/server.key -out /etc/nginx/tls/server.csr
$ sudo openssl x509 -req -in /etc/nginx/tls/server.csr -days 365 -out /etc/nginx/tls/server.crt -CA /etc/nginx/tls/ca.crt -CAkey /etc/nginx/tls/ca.key -extfile /etc/ssl/openssl.cnf -extensions Server
```

- nginxでpathを指定してTLSを有効化
```sh
server {
	listen 443 ssl;
	server_name tls-test-domain.local;

	ssl_certificate /etc/nginx/tls/server.crt;
	ssl_certificate_key /etc/nginx/tls/server.key;

	root /usr/share/nginx/html;
	index index.html;
}
```

- domain nameとipのmappingを`/etc/hosts`に追加する
```
IP tls-test-domain.local
```

- 手元に落として、証明書ストアにストアに登録する
```sh
% scp -i SSH_KEY USER@HOST:REMOTE_PATH LOCAL_PATH
```

