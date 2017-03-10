module Transferatu
  class ScheduleCheck < Sequel::Model
    plugin :timestamps

    many_to_one :schedule

    def self.unverified(limit: 250, by: Time.now())
      # For now, we fetch anything without a record at all. As we
      # establish a baseline check for all schedules, we should
      #  1) include schedules with existing but `not okay`
      Schedule.with_sql(<<-EOF, limit: limit, by: by)
SELECT
  schedules.*
FROM
  schedules LEFT OUTER JOIN schedule_checks ON schedules.uuid = schedule_checks.schedule_id
WHERE
  schedule_checks.uuid IS NULL AND schedules.created_at < :by
LIMIT
  :limit
EOF
    end
  end
end
