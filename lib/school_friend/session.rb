require 'digest'
require 'faraday'
require 'faraday_middleware'
require 'uri'

module SchoolFriend
  class Session
    class ErrorWithResponse < StandardError
      attr_reader :response
      def initialize(message, response = nil)
        @response = response
        super(message)
      end
    end

    class AuthRequired < StandardError
    end

    class ApiError < ErrorWithResponse
    end

    class AuthError < ErrorWithResponse
    end

    attr_reader :options

    def initialize(options = {})
      @options = symbolize_keys(options)
    end

    def access_token=(token)
      options[:access_token] = token
    end

    def access_token
      options[:access_token]
    end

    def refresh_token=(token)
      options[:refresh_token] = token
    end

    def refresh_token
      options[:refresh_token]
    end

    def refresh_access_token
      assert_refresh_token!(__method__)
      response = post_request(api_server + "/oauth/token.do",
                      {"refresh_token" => refresh_token,
                       "client_id" => application_id,
                       "client_secret" => secret_key,
                       "grant_type" => 'refresh_token'})

      assert_oauth_success!(response)
      self.access_token = response.body["access_token"]
      SchoolFriend.logger.debug "#{__method__}: Token received: #{access_token}"

      true
    end

    def oauth2_session?
      !!access_token
    end

    # Returns application key
    #
    # @return [String]
    def application_key
      SchoolFriend.application_key
    end

    # Returns application id
    #
    # @return [String]
    def application_id
      SchoolFriend.application_id
    end

    # Returns application secret key
    #
    # @return [String]
    def secret_key
      SchoolFriend.secret_key
    end

    # Returns signature for signing request params
    #
    # @return [String]
    def signature
      access_token
    end

    # Returns API server
    #
    # @@return [String]
    def api_server
      SchoolFriend.api_server
    end


    # Performs API call to Odnoklassniki
    #
    # @example Performs API call in current scope
    #   school_friend = SchoolFriend::Session.new
    #   school_friend.api_call('widget.getWidgets', wids: 'mobile-header,mobile-footer') # decoded api response
    #
    # @example Force performs API call in session scope
    #   school_friend = SchoolFriend::Session.new
    #   school_friend.api_call('widget.getWidgets', {wids: 'mobile-header,mobile-footer'}, true) # SchoolFriend::Session::AuthRequired
    #
    #
    # @param [String] method API method
    # @param [Hash] params params which should be sent to portal
    # @param [FalseClass, TrueClass] force_session_call says if this call should be performed in session scope
    # @return [Hash]
    def api_call(method, params = {}, force_session_call = false)
      assert_oauth2!(method) if force_session_call
      response = get_request(uri_for_method(method), sign(params))
      assert_api_call_success!(response)
      response.body
    end

    # Returns URI string for a method
    #
    # @param [String] method request method
    # @return [URI::HTTP]
    def uri_for_method(method)
      '/api/' + method.sub('.', '/')
    end

    # Signs params
    #
    # @param [Hash] params
    # @return [Hash] returns signed params
    def sign(params = {})
      params = stringify_keys(additional_params.merge(params))
      digest = params.sort_by(&:first).map{ |key, value| "#{key}=#{value}" }.join

      if oauth2_session?
        params[:sig] = Digest::MD5.hexdigest("#{digest}" + Digest::MD5.hexdigest(access_token + secret_key))
        params[:access_token] = access_token
      else
        params[:sig] = Digest::MD5.hexdigest("#{digest}#{signature}")
      end

      params
    end

    private

    # Returns additional params which are required for all requests.
    # Depends on request scope.
    #
    # @return [Hash]
    def additional_params
      @additional_params ||= { application_key: application_key }
    end

    def post_request(url, params)
      faraday.post(url, params)
    end

    def get_request(url, params)
      faraday.get(url, params)
    end

    def assert_oauth2!(method)
      raise AuthRequired, "session was initialized without access token, calling #{method} doesn't make sense" unless oauth2_session?
    end

    def assert_refresh_token!(method)
      raise ArgumentError, "session was initialized without refresh token, calling #{method} doesn't make sense" unless refresh_token
    end

    def assert_oauth_success!(response)
      body = response.body
      if body.has_key?("error")
        SchoolFriend.logger.error "#{__method__}: failed to refresh access token - #{body["error"]}"
        raise AuthError.new("#{body['error']}: #{body['error_description']}", response)
      end
    end

    def assert_api_call_success!(response)
      body = response.body
      if body.kind_of?(Hash) && body.key?('error_code')
        SchoolFriend.logger.error "#{__method__}: api call error - #{body["error_msg"]}"
        raise ApiError.new("Error #{body['error_code']}: #{body['error_msg']}", response)
      end
    end

    def faraday
      @faraday ||= Faraday.new(api_server) do |conn|
        conn.request :url_encoded
        conn.response :raise_error
        conn.response :json, :content_type => /\bjson$/
        conn.adapter Faraday.default_adapter
      end
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), result|
        if key.respond_to?(:to_sym)
          result[key.to_sym] = value
        else
          result[key] = value
        end
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(key, value), result|
        result[key.to_s] = value
      end
    end

    SchoolFriend::REST_NAMESPACES.each do |namespace|
      class_eval <<-EOS, __FILE__, __LINE__ + 1
        def #{namespace}
          SchoolFriend::REST::#{namespace.capitalize.gsub(/_([a-z])/) { $1.upcase }}.new(self)
        end
      EOS
    end
  end
end
