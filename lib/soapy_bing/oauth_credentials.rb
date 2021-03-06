# frozen_string_literal: true

require 'httparty'

module SoapyBing
  class OauthCredentials
    class TokenRefreshError < StandardError; end

    TOKEN_URL = 'https://login.live.com/oauth20_token.srf'
    SANDBOX_TOKEN_URL = 'https://login.live-int.com/oauth20_token.srf'

    attr_reader :client_id, :client_secret, :refresh_token

    def initialize(oauth_options = {})
      param_guard = ParamGuard.new(oauth_options, env_namespace: 'BING_ADS_OAUTH')
      @client_id = param_guard.require!(:client_id)
      @client_secret = param_guard.require!(:client_secret)
      @refresh_token = param_guard.require!(:refresh_token)
    end

    def access_token
      @access_token ||= request_access_token
    end

    private

    def request_access_token
      resp = HTTParty.post(token_url, body: access_token_params)

      if resp.code != 200
        raise TokenRefreshError, "#{resp['error_description']} (#{resp['error']})"
      end

      resp['access_token']
    end

    def token_url
      ENV['BING_ADS_SANDBOX'] == '1' ? SANDBOX_TOKEN_URL : TOKEN_URL
    end

    def access_token_params
      {
        client_id: client_id,
        client_secret: client_secret,
        grant_type: 'refresh_token',
        refresh_token: refresh_token
      }
    end
  end
end
