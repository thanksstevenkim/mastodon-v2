# frozen_string_literal: true

module NoriSearch
  class ShadowImporter
    extend DatabaseHelper

    SUFFIX = 'nori_v1'

    class MissingIndex < StandardError; end
    class UnexpectedTarget < StandardError; end
    class LegacyImportFailed < StandardError; end
    class ImportFailed < StandardError; end
    class IncompleteDeletion < StandardError; end

    def self.enabled?
      ENV['ES_NORI_SHADOW_WRITES_ENABLED'] == 'true'
    end

    def self.import!(index_class, ids)
      return true unless enabled?
      return true unless [StatusesIndex, PublicStatusesIndex].include?(index_class)

      targets = IndexTargets.new(
        base_name: index_class.base_name,
        prefix: index_class.prefix
      )

      valid_target = index_class.index_name == targets.legacy &&
                     index_class.index_name(suffix: SUFFIX) == targets.nori
      raise UnexpectedTarget, 'Nori index name mismatch' unless valid_target

      raise MissingIndex, "Nori target unavailable: #{targets.nori}" unless index_class.client.indices.exists(index: targets.nori)

      imported = index_class.import!(ids, suffix: SUFFIX)
      raise ImportFailed, 'Nori batch import failed' unless imported

      reconcile_public_statuses!(index_class, ids) if index_class == PublicStatusesIndex

      true
    end

    def self.reconcile_public_statuses!(index_class, ids)
      with_primary do
        eligible_ids = index_class.adapter.default_scope.where(id: ids).pluck(:id).map(&:to_s)
        ineligible_ids = ids.map(&:to_s).uniq - eligible_ids

        if ineligible_ids.any?
          raise LegacyImportFailed, 'Legacy reconciliation failed' unless index_class.import!(ineligible_ids)
          raise ImportFailed, 'Nori reconciliation failed' unless index_class.import!(ineligible_ids, suffix: SUFFIX)
        end
      end
    end

    def self.remove_public_account!(account_id)
      return true unless enabled?

      raise ArgumentError, 'Invalid account ID' unless account_id.is_a?(Integer) && account_id.positive?

      index_class = PublicStatusesIndex
      targets = IndexTargets.new(
        base_name: index_class.base_name,
        prefix: index_class.prefix
      )

      valid_target = index_class.index_name == targets.legacy &&
                     index_class.index_name(suffix: SUFFIX) == targets.nori
      raise UnexpectedTarget, 'Nori index name mismatch' unless valid_target

      client = index_class.client

      raise MissingIndex, "Nori target unavailable: #{targets.nori}" unless client.indices.exists(index: targets.nori)

      response = client.delete_by_query(
        index: targets.nori,
        body: { query: { term: { account_id: account_id } } },
        refresh: true,
        conflicts: 'abort',
        wait_for_completion: true
      )

      result = response.body

      completed = result.is_a?(Hash) &&
                  result['timed_out'] == false &&
                  result['failures'] == [] &&
                  result['version_conflicts'].zero? &&
                  result.fetch('_shards', {}).fetch('failed', 0).zero?
      raise IncompleteDeletion, 'Nori account deletion incomplete' unless completed

      true
    end
  end
end
