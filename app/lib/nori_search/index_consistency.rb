# frozen_string_literal: true

module NoriSearch
  class IndexConsistency
    extend DatabaseHelper

    MAX_IDS = 100
    FOUND_VALUES = [true, false].freeze

    class UnsafeEnvironment < StandardError; end
    class UnsafeTarget < StandardError; end
    class InvalidResponse < StandardError; end

    class Mismatch < StandardError
      attr_reader :issues

      def initialize(issues)
        @issues = issues
        super("Nori consistency mismatch for #{issues.size} status IDs")
      end
    end

    def self.verify!(kind:, ids:)
      safe_environment = Rails.env.test? &&
                         ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true' &&
                         ShadowImporter.enabled?
      raise UnsafeEnvironment, 'Nori audit requires an isolated test environment' unless safe_environment
      raise ArgumentError, 'Invalid status IDs' unless valid_ids?(ids)

      index_class = BackfillCheckpoint.index_for(kind)
      targets = IndexTargets.new(base_name: index_class.base_name, prefix: index_class.prefix)
      valid_target = index_class.index_name == targets.legacy &&
                     index_class.index_name(suffix: ShadowImporter::SUFFIX) == targets.nori
      raise ShadowImporter::UnexpectedTarget, 'Nori index name mismatch' unless valid_target

      client = index_class.client
      [targets.legacy, targets.nori].each do |name|
        raise ShadowImporter::MissingIndex, "Index unavailable: #{name}" unless client.indices.exists?(index: name)
      end

      legacy = fetch_documents!(client, targets.legacy, ids)
      nori = fetch_documents!(client, targets.nori, ids)
      expected = expected_permissions(index_class, kind, ids)
      issues = compare(kind, ids, expected, legacy, nori)
      raise Mismatch, issues if issues.any?

      { kind: kind, checked: ids.size }
    end

    def self.valid_ids?(ids)
      ids.is_a?(Array) && ids.size.between?(1, MAX_IDS) &&
        ids.all? { |id| id.is_a?(Integer) && id.positive? } && ids.uniq == ids
    end

    def self.fetch_documents!(client, name, ids)
      resolved = client.indices.get(index: name).body
      raise UnsafeTarget, "Not a concrete index: #{name}" unless resolved.keys == [name]

      docs = client.mget(index: name, body: { ids: ids }).body.fetch('docs')
      valid = docs.is_a?(Array) &&
              docs.pluck('_id') == ids.map(&:to_s) &&
              docs.all? do |doc|
                doc['_index'] == name && FOUND_VALUES.include?(doc['found']) &&
                  (doc['found'] == false || doc['_source'].is_a?(Hash))
              end
      raise InvalidResponse, "Unexpected Elasticsearch response: #{name}" unless valid

      docs.to_h { |doc| [doc.fetch('_id'), doc['found'] ? doc.fetch('_source') : nil] }
    end

    def self.expected_permissions(index_class, kind, ids)
      with_primary do
        index_class.adapter.default_scope.where(id: ids).each_with_object({}) do |status, result|
          allowed = kind == 'statuses' ? status.searchable_by.sort : nil
          result[status.id.to_s] = allowed if kind == 'public_statuses' || allowed.any?
        end
      end
    end

    def self.compare(kind, ids, expected, legacy, nori)
      ids.each_with_object({}) do |id, result|
        key = id.to_s
        old_doc = legacy.fetch(key)
        new_doc = nori.fetch(key)
        eligible = expected.key?(key)
        reasons = []

        if eligible
          reasons << 'legacy_missing' unless old_doc
          reasons << 'nori_missing' unless new_doc
        else
          reasons << 'legacy_unexpected' if old_doc
          reasons << 'nori_unexpected' if new_doc
        end

        if eligible && kind == 'statuses'
          reasons << 'legacy_acl_mismatch' if old_doc && !acl_matches?(old_doc, expected.fetch(key))
          reasons << 'nori_acl_mismatch' if new_doc && !acl_matches?(new_doc, expected.fetch(key))
        end

        content_differs = old_doc && new_doc && old_doc.except('searchable_by') != new_doc.except('searchable_by')
        reasons << 'source_mismatch' if content_differs
        result[key] = reasons if reasons.any?
      end
    end

    def self.acl_matches?(document, expected)
      actual = document['searchable_by']
      actual.is_a?(Array) && actual.all?(Integer) && actual.sort == expected
    end
  end
end
