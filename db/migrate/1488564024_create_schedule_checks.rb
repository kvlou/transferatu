Sequel.migration do
  change do
    create_table(:schedule_checks) do
      uuid         :uuid, default: Sequel.function(:uuid_generate_v4), primary_key: true
      timestamptz  :created_at, default: Sequel.function(:now), null: false
      timestamptz  :updated_at
      foreign_key  :schedule_id, :schedules, type: :uuid, index: true
      boolean      :okay
      text         :notes
    end
  end
end
