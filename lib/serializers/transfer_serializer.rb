module Transferatu::Serializers
  class Transfer < Base
    structure(:default) do |transfer|
      basic_structure(transfer)
    end

    structure(:verbose) do |transfer|
      response = basic_structure(transfer)
      response[:logs] = transfer.logs(limit: nil).reject do |item|
        item.level == 'internal'
      end.sort_by(&:created_at).map do |item|
        {
          created_at: item.created_at,
          level:      item.level,
          message:    item.message
        }
      end
      response
    end

    def self.basic_structure(transfer)
      response = {
        uuid: transfer.uuid,
        num:  transfer.transfer_num,

        from_name: transfer.from_name,
        from_type: transfer.from_type,
        from_url:  transfer.from_url,
        to_name:   transfer.to_name,
        to_type:   transfer.to_type,
        to_url:    transfer.to_url,
        options:   transfer.options,

        source_bytes:    transfer.source_bytes,
        processed_bytes: transfer.processed_bytes,
        succeeded:       transfer.succeeded,
        warnings:        (transfer.warnings || 0),

        created_at:  transfer.created_at,
        started_at:  transfer.started_at,
        canceled_at: transfer.canceled_at,
        updated_at:  transfer.updated_at,
        finished_at: transfer.finished_at,
        deleted_at:  transfer.deleted_at,
        purged_at:   transfer.purged_at,

        num_keep: transfer.num_keep
      }

      unless transfer.schedule_id.nil?
        response[:schedule] = { uuid: transfer.schedule_id }
      end

      response
    end
  end
end
