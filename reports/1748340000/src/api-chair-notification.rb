# /api/chair/notificationを部分的に抜粋
# ridesテーブルから最新の1件を取得 -> まずこのクエリを疑ってみる(indexは作られていますか？)

# GET /api/chair/notification
    get '/notification' do
      response = db_transaction do |tx|
        ride = tx.xquery('SELECT * FROM rides WHERE chair_id = ? ORDER BY updated_at DESC LIMIT 1', @current_chair.id).first
        unless ride
          halt json(data: nil, retry_after_ms: 30)
        end

        yet_sent_ride_status = tx.xquery('SELECT * FROM ride_statuses WHERE ride_id = ? AND chair_sent_at IS NULL ORDER BY created_at ASC LIMIT 1', ride.fetch(:id)).first
        status =
          if yet_sent_ride_status.nil?
            get_latest_ride_status(tx, ride.fetch(:id))
          else
            yet_sent_ride_status.fetch(:status)
          end

        user = tx.xquery('SELECT * FROM users WHERE id = ? FOR SHARE', ride.fetch(:user_id)).first

        unless yet_sent_ride_status.nil?
          tx.xquery('UPDATE ride_statuses SET chair_sent_at = CURRENT_TIMESTAMP(6) WHERE id = ?', yet_sent_ride_status.fetch(:id))
        end

        {
          data: {
            ride_id: ride.fetch(:id),
            user: {
              id: user.fetch(:id),
              name: "#{user.fetch(:firstname)} #{user.fetch(:lastname)}",
            },
            pickup_coordinate: {
              latitude: ride.fetch(:pickup_latitude),
              longitude: ride.fetch(:pickup_longitude),
            },
            destination_coordinate: {
              latitude: ride.fetch(:destination_latitude),
              longitude: ride.fetch(:destination_longitude),
            },
            status:,
          },
          retry_after_ms: 30,
        }
      end

      json(response)
    end
