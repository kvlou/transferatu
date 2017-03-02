Sequel.migration do
  no_transaction
  change do
    alter_table(:transfers) do
      add_index(:schedule_id, concurrently: true)
    end
  end
end
