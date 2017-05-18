module Transferatu
  module Mediators::Transfers
    class Evictor < Mediators::Base
      def initialize(transfer:)
        @transfer = transfer
      end

      def call
        # This evictor is to delete manual backups (schedule_id is null)
        # that are more than retention limits (saved as num_keep, e.g. for
        # hobby-basic database, it's 5).
        # Evictor only runs when the current transfer type is a manual backup.
        #  * backups: from_type 'pg_dump', to_type 'gof3r'
        #  * restores: from_type NOT 'pg_dump', to_type 'pg_restore'
        #  * copies: from_type 'pg_dump', to_type 'pg_restore'
        return if @transfer.to_type == 'pg_restore'
        return unless @transfer.schedule_id.nil?

        # TODO: right now, we explicitly hard-code 'gof3r' target
        # transfers for expiration here; ideally we should have
        # better-defined semantics
        to_delete = @transfer.group.transfers_dataset.present
          .where(from_name: @transfer.from_name,
                 to_type: 'gof3r', schedule_id: nil,
                 succeeded: true)
          .order_by(Sequel.desc(:created_at))
          .offset(@transfer.num_keep)
        to_delete.each do |evicted|
          evicted.destroy
        end
      end
    end
  end
end
