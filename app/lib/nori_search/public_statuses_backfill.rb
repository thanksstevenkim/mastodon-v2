# frozen_string_literal: true

module NoriSearch
  class PublicStatusesBackfill
    extend DatabaseHelper

    MAX_BATCH_SIZE = 100

    class UnsafeEnvironment < StandardError; end
    class ImportFailed < StandardError; end

    def self.run!(after_id:, batch_size:)
      backfill_allowed = Rails.env.test? || (Rails.env.production? && ENV['ES_NORI_BACKFILL_ENABLED'] == 'true')
      safe_environment = backfill_allowed &&
                         ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true' &&
                         ShadowImporter.enabled?
      raise UnsafeEnvironment, 'Nori backfill is restricted to Nori-enabled test environments' unless safe_environment

      raise ArgumentError, 'Invalid cursor' unless after_id.is_a?(Integer) && after_id >= 0
      raise ArgumentError, 'Invalid batch size' unless batch_size.is_a?(Integer) && batch_size.between?(1, MAX_BATCH_SIZE)

      index_class = PublicStatusesIndex
      targets = IndexTargets.new(base_name: index_class.base_name, prefix: index_class.prefix)
      valid_target = index_class.index_name == targets.legacy &&
                     index_class.index_name(suffix: ShadowImporter::SUFFIX) == targets.nori
      raise ShadowImporter::UnexpectedTarget, 'Nori index name mismatch' unless valid_target
      raise ShadowImporter::MissingIndex, "Nori target unavailable: #{targets.nori}" unless index_class.client.indices.exists(index: targets.nori)

      with_primary do
        ids = Status.unscoped.kept.indexable
          .where('statuses.id > ?', after_id)
          .reorder(id: :asc)
          .limit(batch_size + 1)
          .pluck(:id)

        batch = ids.first(batch_size)

        if batch.any?
          raise ImportFailed, 'Nori batch import failed' unless index_class.import!(batch, suffix: ShadowImporter::SUFFIX)

          eligible_ids = index_class.adapter.default_scope.where(id: batch).pluck(:id)
          revoked_ids = batch - eligible_ids

          reconciliation_failed = revoked_ids.any? && !index_class.import!(revoked_ids, suffix: ShadowImporter::SUFFIX)
          raise ImportFailed, 'Nori revocation reconciliation failed' if reconciliation_failed
        end

        {
          after_id: batch.last || after_id,
          processed: batch.size,
          done: ids.size <= batch_size,
        }
      end
    end
  end
end
