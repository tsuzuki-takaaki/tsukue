# MEMO: 一旦最も待たせているリクエストに適当な空いている椅子マッチさせる実装とする。おそらくもっといい方法があるはず…
# ここから明らかにマッチングのロジックを改善できることがわかる
#
# やっていること
# chairが割り当てられていないride(椅子待ち)を1件取得してマッチング
# -> 複数件にできるよね(マッチング数が増えた方がいいので確率的に)
# matchingのpolling期間は0.5秒(500ms)になっていて、サーバーのログを見ると処理時間は余っているので複数件取得してiterateして確かめる見たいなことができる
# 重要なのが、ログを見て時間が余っているということを確認すること

# frozen_string_literal: true

require 'isuride/base_handler'

module Isuride
  class InternalHandler < BaseHandler
    # このAPIをインスタンス内から一定間隔で叩かせることで、椅子とライドをマッチングさせる
    # GET /api/internal/matching
    get '/matching' do
      # MEMO: 一旦最も待たせているリクエストに適当な空いている椅子マッチさせる実装とする。おそらくもっといい方法があるはず…
      rides = db.query('SELECT * FROM rides WHERE chair_id IS NULL ORDER BY created_at LIMIT 1').first

      if rides.count == 0
        halt 204
      end

      rides.each do |ride|
        10.times do
          matched = db.query('SELECT * FROM chairs INNER JOIN (SELECT id FROM chairs WHERE is_active = TRUE ORDER BY RAND() LIMIT 1) AS tmp ON chairs.id = tmp.id LIMIT 1').first
          unless matched
            halt 204
          end

          empty = db.xquery('SELECT COUNT(*) = 0 FROM (SELECT COUNT(chair_sent_at) = 6 AS completed FROM ride_statuses WHERE ride_id IN (SELECT id FROM rides WHERE chair_id = ?) GROUP BY ride_id) is_completed WHERE completed = FALSE', matched.fetch(:id), as: :array).first[0]
          if empty > 0
            db.xquery('UPDATE rides SET chair_id = ? WHERE id = ?', matched.fetch(:id), ride.fetch(:id))
            break
          end
        end
      end

      204
    end
  end
end
