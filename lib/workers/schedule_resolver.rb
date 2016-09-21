module Transferatu
  class ScheduleResolver
    # Attempt to resolve a schedule to a hash containing data for
    # creating a transfer, as if coming from a normal POST to the
    # +/groups/:name/transfers+ endpoint. If the schedule callback url
    # returns 404 or 410, return nil.
    def resolve(schedule)
      endpoint = resource(schedule.callback_url,
                          schedule.group.user.name,
                          schedule.group.user.callback_password)
      result = begin
                 endpoint.get
               rescue RestClient::Gone, RestClient::ResourceNotFound
                 return nil
               end
      JSON.parse(result)
    end

    private

    def resource(callback_url, user, password)
      RestClient::Resource.new(callback_url,
                               user: user,
                               password: password,
                               headers: { content_type: 'application/octet-stream',
                                         accept: 'application/octet-stream' })
    end
  end
end
