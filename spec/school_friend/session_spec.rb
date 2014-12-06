require 'spec_helper'

describe SchoolFriend::Session do
  subject { SchoolFriend.session(access_token: $access_token, refresh_token: $refresh_token) }

  describe "#api_call" do
    before do
      stub_request(:any, /api\.odnoklassniki\.ru\/api\/url\/getInfo/).to_return(body: '{"type":"UNKNOWN"}', headers: { content_type: 'application/json' })
    end

    it "makes a request to odnoklassniki api server and parses json response" do
      response = subject.api_call('url.getInfo', url: 'http://ok.com/example')
      response.should == {"type" => "UNKNOWN"}
    end
  end
end
