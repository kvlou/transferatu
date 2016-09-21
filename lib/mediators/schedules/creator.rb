require_relative 'helpers'

module Transferatu
  module Mediators::Schedules
    class Creator < Mediators::Base
      include ScheduleValidator

      def initialize(group:, name:, callback_url:,
                     hour:, days:, timezone:,
                     retain_weeks:, retain_months:)
        @group = group
        @name = name
        @callback_url = callback_url
        @hour = hour
        @days = days
        @tz = timezone

        @retain_weeks = retain_weeks
        @retain_months = retain_months
      end

      def call
        map_days(@days)
        verify_timezone(@tz)
        verify_callback(@callback_url)

        sched_opts = { name: @name, callback_url: @callback_url,
                       hour: @hour, dows: map_days(@days), timezone: @tz }

        unless @retain_weeks.nil?
          sched_opts[:retain_weeks] = @retain_weeks.to_i
        end
        unless @retain_months.nil?
          sched_opts[:retain_months] = @retain_months.to_i
        end
        @group.add_schedule(sched_opts)
      end
    end
  end
end
