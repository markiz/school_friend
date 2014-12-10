require 'bundler/setup'
require 'webmock/rspec'
require 'school_friend'

RSpec.configure do |c|
  c.include WebMock::API
  c.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
  end
end

SchoolFriend.application_id = '1234567890'
SchoolFriend.application_key = 'ABACABACBACAB'
SchoolFriend.secret_key = 'FFFAAAEEEBBBCCCAAADDD'
SchoolFriend.api_server = 'http://api.odnoklassniki.ru'

$access_token = 'ABCDEF0123456789'
$refresh_token = 'DEADBABE0123456'
