Sequel.migration do
  no_transaction
  change do
    alter_table(:transfers) do
      add_index(%i(schedule_id created_at), where: {deleted_at: nil}, concurrently: true)
    end
  end
end
