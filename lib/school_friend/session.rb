require 'digest'
require 'faraday'
require 'faraday_middleware'
require 'uri'
def keys_to_symbols! (_hash)
  _hash.keys.each do |key|
    _hash[(key.to_sym rescue key) || key] = _hash.delete(key)
  end

  return _hash
end

module SchoolFriend
  class Session
    class ErrorWithResponse < StandardError
      attr_reader :response
      def initialize(message, response = nil)
        @response = response
        super(message)
      end
    end

    class ApiError < ErrorWithResponse
    end

    class AuthError < ErrorWithResponse
    end

    class RequireSessionScopeError < ArgumentError
    end

    class OauthCodeAuthenticationFailedError < StandardError
    end

    attr_reader :options, :session_scope

    def initialize(options = {})
      @options       = keys_to_symbols!(options)
      @session_scope = (options[:session_key] && options[:session_secret_key]) || \
                           options[:oauth_code] || \
                           (options[:access_token] && options[:refresh_token])

    # only has oauth_code, get access_token
    if options[:oauth_code]
      response, data = \
        post_request("/oauth/token.do",
                      {"code" => options[:oauth_code], "redirect_uri" => "http://127.0.0.1:2000",
                       "client_id" => SchoolFriend.application_id, "client_secret" => SchoolFriend.secret_key,
                       "grant_type" => 'authorization_code'})

        if response.is_a?(Net::HTTPSuccess)
          response = JSON(response.body)

          if response.has_key?("error")
              raise OauthCodeAuthenticationFailedError, "failed to use oauth_code for authentication: #{response["error"]}: #{response["error_description"]}"
          end

          options[:access_token] = response["access_token"]
          options[:refresh_token] = response["refresh_token"]

          SchoolFriend.logger.debug "Tokens received: #{options[:access_token]} #{options[:refresh_token]}"
        else
          raise OauthCodeAuthenticationFailedError, "failed to use oauth_code for authentication - Request Failed"
        end

        options.delete(:oauth_code)
      end
    end

    def refresh_access_token
      assert_oauth2!(__method__)
      response = post_request(api_server + "/oauth/token.do",
                      {"refresh_token" => options[:refresh_token],
                       "client_id" => SchoolFriend.application_id,
                       "client_secret" => SchoolFriend.secret_key,
                       "grant_type" => 'refresh_token'})

      assert_oauth_success!(response)
      options[:access_token] = response.body["access_token"]
      SchoolFriend.logger.debug "#{__method__}: Token received: #{options[:access_token]}"

      true
    end

    # Returns true if API call is performed in session scope
    #
    # @return [TrueClass, FalseClass]
    alias_method :session_scope?, :session_scope

    # Returns true if API call is performed in application scope
    #
    # @return [TrueClass, FalseClass]
    def application_scope?
      not session_scope?
    end

    def oauth2_session?
      options[:access_token] && options[:refresh_token]
    end

    # Returns application key
    #
    # @return [String]
    def application_key
      SchoolFriend.application_key
    end

    # Returns signature for signing request params
    #
    # @return [String]
    def signature
      unless session_scope?
        return SchoolFriend.secret_key
      end

      options[:access_token] || options[:session_secret_key]
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
    #   school_friend.api_call('widget.getWidgets', wids: 'mobile-header,mobile-footer') # Net::HTTPResponse
    #
    # @example Force performs API call in session scope
    #   school_friend = SchoolFriend::Session.new
    #   school_friend.api_call('widget.getWidgets', {wids: 'mobile-header,mobile-footer'}, true) # SchoolFriend::Session::RequireSessionScopeError
    #
    #
    # @param [String] method API method
    # @param [Hash] params params which should be sent to portal
    # @param [FalseClass, TrueClass] force_session_call says if this call should be performed in session scope
    # @return [Net::HTTPResponse]
    def api_call(method, params = {}, force_session_call = false)
      raise RequireSessionScopeError.new('This API call requires session scope') if force_session_call and application_scope?
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
      params = additional_params.merge(params)
      digest = params.sort_by(&:first).map{ |key, value| "#{key}=#{value}" }.join

      if oauth2_session?
        params[:sig] = Digest::MD5.hexdigest("#{digest}" + Digest::MD5.hexdigest(options[:access_token] + SchoolFriend.secret_key))
        params[:access_token] = options[:access_token]
      else
        params[:sig] = Digest::MD5.hexdigest("#{digest}#{signature}")
      end

      params
    end

    # Returns additional params which are required for all requests.
    # Depends on request scope.
    #
    # @return [Hash]
    def additional_params
      @additional_params ||= if session_scope?
        if oauth2_session?
          {application_key: application_key}
        else
          {application_key: application_key, session_key: options[:session_key]}
        end
      else
        {application_key: application_key}
      end
    end

    def post_request(url, params)
      faraday.post(url, params)
    end

    def get_request(url, params)
      faraday.get(url, params)
    end

    def assert_oauth2!(method)
      raise ArgumentError, "session was initialized without oauth params, calling #{method} doesn't make sense" unless oauth2_session?
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
      if body.key?('error_code')
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

    SchoolFriend::REST_NAMESPACES.each do |namespace|
      class_eval <<-EOS, __FILE__, __LINE__ + 1
        def #{namespace}
          SchoolFriend::REST::#{namespace.capitalize.gsub(/_([a-z])/) { $1.upcase }}.new(self)
        end
      EOS
    end
  end
end
