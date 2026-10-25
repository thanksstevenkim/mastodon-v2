# frozen_string_literal: true

module NoriSearch
  class ShadowImporter
    SUFFIX = 'nori_v1'

    class MissingIndex < StandardError; end
    class UnexpectedTarget < StandardError; end
    class LegacyImportFailed < StandardError; end
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

      index_class.import!(ids, suffix: SUFFIX)
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

      result = client.delete_by_query(
        index: targets.nori,
        body: { query: { term: { account_id: account_id } } },
        refresh: true,
        conflicts: 'abort',
        wait_for_completion: true
      )

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
