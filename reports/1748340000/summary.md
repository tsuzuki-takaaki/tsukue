## Summary

1. alpを使って遅いエンドポイントを特定しよう
    - ソート条件はp99じゃなくて、SUMで
1. どのテーブルにどんなクエリが実行されているのか確認しよう
    - performance_schemaを見るのだ
1. pt-query-digestは使わずにMySQLのmetricsを取得しよう
    - mirakuiさんのやつを使おう
    - 使う時はperformance_schemaを都度更新するように気をつけよう
1. migrationは、schema用のファイルを変更してinit.shの実行
    - `webapp/sql/`にあるschemaファイルを正として変更を加えていくのだ
1. indexを作成する際には、ASC, DESCの存在を忘れるな
    - 明示しない場合はASCになっているのだ
1. ログを確認したい問題は、stdoutに吐けばjournaldで確認できることがわかった
    - 都度デバッグしたいみたいな時にはputsでも確認できる
1. そのアプリケーションの処理はクエリで解決できないか？
    - アプリケーションで実行されている、SQLで取得したデータを加工する処理はクエリで解決できないか？
    - N+1含め
    - そのためにアプリケーションにおいて何をやっているかの理解が大切
1. アプリケーションの仕様を読まないとわからないものが結構ある
    - 実は複雑になっているロジックが不要だったりする
1. scoreが落ちることはあまり問題ではない
    - **ボトルネックを解消できた == 加点の方程式は成立していない**
    - どうしたら加点するかはちゃんとレギュレーションを読まないといけない
    - ボトルネックを取り除いたら、他のところにボトルネックが遷移していくのがisucon
        - その遷移を続けて初めて高得点のチャンスがやってくるのだ
1. N+1の解消にはかなりドメイン知識が関わっている
    - レギュレーションを見ると、実は計算しなくて良い処理などが多く含まれる
1. 点数が上がる改善と、システム負荷が解消する改善を分けて考えないといけない
    - システム負荷を改善すればいいというものでもなかったりする
