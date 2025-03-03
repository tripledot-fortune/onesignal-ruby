# frozen_string_literal: true

require 'faraday'

module OneSignal
  class Client
    class ApiError < RuntimeError; end
    class ClientError < ApiError; end
    class ApiRateLimitError < ClientError; end
    class InvalidExternalUserIdsError < ClientError; end
    class InvalidPlayerIdsError < ClientError; end
    class TagsLimitError < ClientError; end
    class ServerError < ApiError; end

    ERROR_MESSAGE_MAPPING = {
      'API rate limit exceeded' => ApiRateLimitError,
      'invalid_external_user_ids' => InvalidExternalUserIdsError,
      'invalid_player_ids' => InvalidPlayerIdsError
    }.freeze

    def initialize app_id, api_key, api_url
      @app_id = app_id
      @api_key = api_key
      @api_url = api_url
      @conn = ::Faraday.new(url: api_url) do |faraday|
        # faraday.response :logger do |logger|
        #   logger.filter(/(api_key=)(\w+)/, '\1[REMOVED]')
        #   logger.filter(/(Basic )(\w+)/, '\1[REMOVED]')
        # end
        faraday.adapter Faraday.default_adapter
      end
    end

    def create_notification notification
      post 'notifications', notification
    end

    def fetch_notification notification_id
      get "notifications/#{notification_id}"
    end

    def fetch_notifications page_limit: 50, page_offset: 0, kind: nil
      url = "notifications?limit=#{page_limit}&offset=#{page_offset}"
      url = kind ? "#{url}&kind=#{kind}" : url
      get url
    end

    def fetch_players
      get 'players'
    end

    def fetch_player player_id
      get "players/#{player_id}"
    end

    def delete_player player_id
      delete "players/#{player_id}"
    end

    def csv_export extra_fields: nil, last_active_since: nil, segment_name: nil
      post "players/csv_export?app_id=#{@app_id}",
        extra_fields: extra_fields,
        last_active_since: last_active_since&.to_i&.to_s,
        segment_name: segment_name
    end

    private

    def create_body payload
      body = payload.as_json.delete_if { |_, v| v.nil? }
      body['app_id'] = @app_id
      body
    end

    def delete url
      res = @conn.delete do |req|
        req.url url, app_id: @app_id
        req.headers['Authorization'] = "Basic #{@api_key}"
      end

      handle_errors res
    end

    def post url, body
      res = @conn.post do |req|
        req.url url
        req.body = create_body(body).to_json
        req.headers['Content-Type'] = 'application/json'
        req.headers['Authorization'] = "Basic #{@api_key}"
      end

      handle_errors res
    end

    def get url
      res = @conn.get do |req|
        req.url url, app_id: @app_id
        req.headers['Content-Type'] = 'application/json'
        req.headers['Authorization'] = "Basic #{@api_key}"
      end

      handle_errors res
    end

    def handle_errors res
      json = begin
               JSON.parse(res.body)
             rescue JSON::ParserError, TypeError
               {}
             end
      errors = json.fetch('errors', [])
      if res.status > 499
        raise ServerError, errors.first || "Error code #{res.status}"
      elsif errors.any?
        error = errors.detect { |key, _v| ERROR_MESSAGE_MAPPING.keys.include?(key) }
        raise ERROR_MESSAGE_MAPPING[error[0]].new(error[1]) if error && error.is_a?(Array)
        raise ERROR_MESSAGE_MAPPING[error].new(error) if error
        raise ClientError, errors.first
      elsif res.status > 399
        raise ClientError, errors.first || "Error code #{res.status} #{res.body}"
      end

      res
    end
  end
end
