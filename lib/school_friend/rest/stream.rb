module SchoolFriend
  module REST
    class Stream
      include APIMethods

      api_method :get,     session_only: true
      api_method :publish
    end
  end
end
