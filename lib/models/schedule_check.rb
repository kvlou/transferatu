module Transferatu
  class ScheduleCheck < Sequel::Model
    plugin :timestamps

    many_to_one :schedule

    def self.unverified(limit: 250)
      # For now, we fetch anything without a record at all. As we
      # establish a baseline check for all schedules, we should
      #  1) include schedules with existing but `not okay`
      #  2) include deleted schedules
      Schedule.with_sql(<<-EOF, limit: limit)
SELECT
  schedules.*
FROM
  schedules LEFT OUTER JOIN schedule_checks ON schedules.uuid = schedule_checks.schedule_id
WHERE
  schedule_checks.uuid IS NULL AND schedules.deleted_at IS NULL
LIMIT
  :limit
EOF
    end
  end
end
