# frozen_string_literal: true

module NoriSearch
  class StatusesBackfill
    extend DatabaseHelper

    MAX_BATCH_SIZE = 100
    PHASES = %w(local_statuses local_mentions local_favourites local_votes local_bookmarks).freeze

    class UnsafeEnvironment < StandardError; end
    class ImportFailed < StandardError; end

    def self.run!(phase:, after_id:, batch_size:)
      backfill_allowed = Rails.env.test? || (Rails.env.production? && ENV['ES_NORI_BACKFILL_ENABLED'] == 'true')
      safe_environment = backfill_allowed &&
                         ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true' &&
                         ShadowImporter.enabled?
      raise UnsafeEnvironment, 'Nori backfill requires a Nori-enabled test environment' unless safe_environment
      raise ArgumentError, 'Invalid phase' unless PHASES.include?(phase)
      raise ArgumentError, 'Invalid cursor' unless after_id.is_a?(Integer) && after_id >= 0
      raise ArgumentError, 'Invalid batch size' unless batch_size.is_a?(Integer) && batch_size.between?(1, MAX_BATCH_SIZE)

      index_class = StatusesIndex
      targets = IndexTargets.new(base_name: index_class.base_name, prefix: index_class.prefix)
      valid_target = index_class.index_name == targets.legacy &&
                     index_class.index_name(suffix: ShadowImporter::SUFFIX) == targets.nori
      raise ShadowImporter::UnexpectedTarget, 'Nori index name mismatch' unless valid_target
      raise ShadowImporter::MissingIndex, "Nori target unavailable: #{targets.nori}" unless index_class.client.indices.exists(index: targets.nori)

      with_primary do
        scope = source_scope(phase)
        source_id = scope.klass.arel_table[:id]
        rows = scope.where(source_id.gt(after_id)).distinct.reorder(source_id.asc).limit(batch_size + 1).to_a
        batch = rows.first(batch_size)
        status_ids = batch.map(&:status_id).uniq

        if status_ids.any?
          raise ImportFailed, 'Nori batch import failed' unless index_class.import!(status_ids, suffix: ShadowImporter::SUFFIX)

          eligible_ids = index_class.adapter.default_scope.where(id: status_ids)
            .select { |status| status.searchable_by.present? }
            .map(&:id)
          ineligible_ids = status_ids - eligible_ids

          reconciliation_failed = ineligible_ids.any? && !index_class.import!(ineligible_ids, suffix: ShadowImporter::SUFFIX)
          raise ImportFailed, 'Nori permission reconciliation failed' if reconciliation_failed
        end

        phase_complete = rows.size <= batch_size
        next_phase = phase_complete ? PHASES[PHASES.index(phase) + 1] : phase

        {
          phase: next_phase,
          after_id: phase_complete ? 0 : batch.last.id,
          processed: batch.size,
          done: next_phase.nil?,
        }
      end
    end

    def self.source_scope(phase)
      case phase
      when 'local_statuses'
        Status.local.select('"statuses"."id", COALESCE("statuses"."reblog_of_id", "statuses"."id") AS status_id')
      when 'local_mentions'
        Mention.where(account: Account.local, silent: false).select(:id, :status_id)
      when 'local_favourites'
        Favourite.where(account: Account.local).select(:id, :status_id)
      when 'local_votes'
        Poll.joins(:votes).where(votes: { account: Account.local }).select(polls: [:id, :status_id])
      when 'local_bookmarks'
        Bookmark.select(:id, :status_id)
      end
    end
  end
end
