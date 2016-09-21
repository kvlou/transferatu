unless ENV["TEST_LOGS"] == "true"
  module Pliny::Log
    def log(data, &block)
      yield if block
    end
  end
end
