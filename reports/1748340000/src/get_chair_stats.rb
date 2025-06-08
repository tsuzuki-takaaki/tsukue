# N+1が起きている代表例
# https://github.com/tsuzuki-takaaki/isucon14-final/blob/main/webapp/ruby/lib/isuride/app_handler.rb#L455C7-L498C10

# やっていること(悪手)
# 特定のchairの乗車情報を全て取得
# その全ての乗車情報を都度取得して、アプリケーション側で何かしらの計算をしている
# -> arrived_at, pickup_at, is_completedをその乗車情報から取得
# -> arrived_at, pickup_atがNULLの場合はiterateを終了して次の要素に
# -> arrived_at, pickup_atがNULLのものは取得する必要がない
# -> created_atがNULLのものは取得する必要がない
#
# やっていること(良手)
# chairの乗車履歴からトータルの乗車回数と評価(星いくつみたいな)を取得している
# -> 仕様を確認すると、rideが完了しない間は評価(evaluation)には値がはいらないようになっている
# https://github.com/isucon/isucon14/blob/main/docs/ISURIDE.md#%E3%83%A9%E3%82%A4%E3%83%89ride
# rideのライフサイクルの最後にあるものがevaluation
# -> evaluationが入っていないレコードはこの処理においては不要
# 終了もしていないし、evaluationも付与されていないから
# -> ridesテーブルのevaluationがNOT NULLなレコードを取得して計算するだけでいい

# before
def get_chair_stats(tx, chair_id)
  rides = tx.xquery('SELECT * FROM rides WHERE chair_id = ? ORDER BY updated_at DESC', chair_id)

  total_rides_count = 0
  total_evaluation = 0.0
  rides.each do |ride|
    ride_statuses = tx.xquery('SELECT * FROM ride_statuses WHERE ride_id = ? ORDER BY created_at', ride.fetch(:id))

    arrived_at = nil
    pickup_at = nil
    is_completed = false
    ride_statuses.each do |status|
      case status.fetch(:status)
      when 'ARRIVED'
        arrived_at = status.fetch(:created_at)
      when 'CARRYING'
        pickup_at = status.fetch(:created_at)
      when 'COMPLETED'
        is_completed = true
      end
    end
    if arrived_at.nil? || pickup_at.nil?
      next
    end
    unless is_completed
      next
    end

    total_rides_count += 1
    total_evaluation += ride.fetch(:evaluation)
  end

  total_evaluation_avg =
    if total_rides_count > 0
      total_evaluation / total_rides_count
    else
      0.0
    end

  {
    total_rides_count:,
    total_evaluation_avg:,
  }
end

# after
def get_chair_stats(tx, chair_id)
  rides = tx.xquery('SELECT * FROM rides WHERE chair_id = ? ORDER BY updated_at DESC', chair_id)
  total_rides_count = rides.count
  total_evaluation = rides.sum{|ride| ride.fetch(:evaluation)}.to_f

  total_evaluation_avg =
    if total_rides_count > 0
      total_evaluation / total_rides_count
    else
      0.0
    end

  {
    total_rides_count:,
    total_evaluation_avg:,
  }
end
