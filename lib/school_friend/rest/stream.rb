module SchoolFriend
  module REST
    class Stream
      include APIMethods

      api_method :get
      api_method :publish
    end
  end
end
