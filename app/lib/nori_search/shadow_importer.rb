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

      unless index_class.index_name == targets.legacy &&
             index_class.index_name(suffix: SUFFIX) == targets.nori
        raise UnexpectedTarget, 'Nori index name mismatch'
      end

      unless index_class.client.indices.exists(index: targets.nori)
        raise MissingIndex, "Nori target unavailable: #{targets.nori}"
      end

      index_class.import!(ids, suffix: SUFFIX)
    end

    def self.remove_public_account!(account_id)
      return true unless enabled?

      unless account_id.is_a?(Integer) && account_id.positive?
        raise ArgumentError, 'Invalid account ID'
      end

      index_class = PublicStatusesIndex
      targets = IndexTargets.new(
        base_name: index_class.base_name,
        prefix: index_class.prefix
      )

      unless index_class.index_name == targets.legacy &&
             index_class.index_name(suffix: SUFFIX) == targets.nori
        raise UnexpectedTarget, 'Nori index name mismatch'
      end

      client = index_class.client

      unless client.indices.exists(index: targets.nori)
        raise MissingIndex, "Nori target unavailable: #{targets.nori}"
      end

      result = client.delete_by_query(
        index: targets.nori,
        body: { query: { term: { account_id: account_id } } },
        refresh: true,
        conflicts: 'abort',
        wait_for_completion: true
      )

      unless result.is_a?(Hash) &&
             result['timed_out'] == false &&
             result['failures'] == [] &&
             result['version_conflicts'] == 0 &&
             result.fetch('_shards', {}).fetch('failed', 0) == 0
        raise IncompleteDeletion, 'Nori account deletion incomplete'
      end

      true
    end

  end
end
