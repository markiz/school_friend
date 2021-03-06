require 'spec_helper'

describe SchoolFriend::Session do
  subject { SchoolFriend.session(access_token: $access_token, refresh_token: $refresh_token) }

  describe "#api_call" do
    before do
      stub_request(:get, %r{api\.odnoklassniki\.ru/api/url/getInfo}).
          with(query: hash_including({url: 'http://ok.com/example'})).
          to_return(body: '{"type":"UNKNOWN"}', headers: { content_type: 'application/json' })
    end

    it "makes a request to odnoklassniki api server and parses json response" do
      response = subject.api_call('url.getInfo', url: 'http://ok.com/example')
      response.should == {"type" => "UNKNOWN"}
    end

    it "raises on api errors" do
       stub_request(:get, %r{api\.odnoklassniki\.ru/api/url/getInfo}).
          to_return(body: '{"error_code":100,"error_msg":"PARAM : Missing required parameter url","error_data":null}', headers: { content_type: 'application/json' })
      expect { subject.api_call('url.getInfo') }.to raise_error(SchoolFriend::Session::ApiError)
    end

    it "handles non-hash responses" do
      stub_request(:get, %r{api\.odnoklassniki\.ru/api/users/getInfo}).
          to_return(body: '[{"uid":"261777630248","name":"Максим Глазунов"}]', headers: { content_type: 'application/json' })
      subject.api_call('users.getInfo', { uids: '261777630248', fields: 'name' }).should ==
          [{'uid' => '261777630248', 'name' => 'Максим Глазунов'}]
    end

    it "raises when session requires authentication and no oauth token is provided" do
      subject.access_token = nil
      expect { subject.api_call('users.getInfo', {}, true) }.to raise_error(SchoolFriend::Session::AuthRequired)
    end

    it "supports quirky json responses" do
      stub_request(:get, %r{api\.odnoklassniki\.ru/api/users/isAppUser}).
          to_return(body: 'true', headers: { content_type: 'application/json' })
      subject.api_call('users.isAppUser').should == true
    end
  end

  describe "#refresh" do
    before do
      stub_request(:post, %r{api\.odnoklassniki\.ru/oauth/token\.do}).
          to_return(body: '{"token_type": "session", "access_token": "abcdef123456"}', headers: { content_type: 'application/json' })
    end

    it "updates its own access token" do
      subject.refresh_access_token
      subject.access_token.should == 'abcdef123456'
    end

    it "raises on errors" do
      stub_request(:post, %r{api\.odnoklassniki\.ru/oauth/token\.do}).
          to_return(body: '{"error": "invalid token", "error_description": "Invalid refresh token structure"}', headers: { content_type: 'application/json' })
      expect { subject.refresh_access_token }.to raise_error(SchoolFriend::Session::AuthError)
    end

    it "raises on non-auth2 sessions" do
      subject.access_token = nil
      subject.refresh_token = nil
      expect { subject.refresh_access_token }.to raise_error(ArgumentError)
    end
  end
end
