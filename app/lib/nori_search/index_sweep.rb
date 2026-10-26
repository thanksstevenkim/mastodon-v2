# frozen_string_literal: true

module NoriSearch
  class IndexSweep
    MAX_BATCH_SIZE = 100
    PUBLIC_SOURCES = %w(database legacy nori).freeze
    STATUS_SOURCES = (StatusesBackfill::PHASES.map { |phase| "db_#{phase}" } + %w(legacy nori)).freeze

    class UnsafeEnvironment < StandardError; end
    class UnsafeTarget < StandardError; end
    class InvalidResponse < StandardError; end

    def self.step!(kind:, source:, after_id:, batch_size:)
      safe_environment = Rails.env.test? &&
                         ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true' &&
                         ShadowImporter.enabled?
      raise UnsafeEnvironment, 'Nori sweep requires a Nori-enabled test environment' unless safe_environment

      sources = sources_for(kind)
      raise ArgumentError, 'Invalid sweep source' unless sources.include?(source)
      raise ArgumentError, 'Invalid cursor' unless after_id.is_a?(Integer) && after_id >= 0
      raise ArgumentError, 'Invalid batch size' unless batch_size.is_a?(Integer) && batch_size.between?(1, MAX_BATCH_SIZE)

      index_class = BackfillCheckpoint.index_for(kind)
      targets = IndexTargets.new(base_name: index_class.base_name, prefix: index_class.prefix)
      valid_target = index_class.index_name == targets.legacy &&
                     index_class.index_name(suffix: ShadowImporter::SUFFIX) == targets.nori
      raise ShadowImporter::UnexpectedTarget, 'Nori index name mismatch' unless valid_target

      client = index_class.client
      [targets.legacy, targets.nori].each do |name|
        resolved = client.indices.get(index: name).body
        raise UnsafeTarget, "Not a concrete index: #{name}" unless resolved.keys == [name]
      end

      rows = if source == 'database'
               public_rows(after_id, batch_size)
             elsif source.start_with?('db_')
               status_rows(source.delete_prefix('db_'), after_id, batch_size)
             else
               index_name = source == 'legacy' ? targets.legacy : targets.nori
               index_rows(client, index_name, after_id, batch_size)
             end

      batch = rows.first(batch_size)
      ids = batch.map(&:last).uniq
      raise InvalidResponse, 'Invalid source status IDs' unless ids.all? { |id| id.is_a?(Integer) && id.positive? }

      IndexConsistency.verify!(kind: kind, ids: ids) if ids.any?

      finished_source = rows.size <= batch_size
      next_source = finished_source ? sources[sources.index(source) + 1] : source

      {
        source: next_source,
        after_id: finished_source ? 0 : batch.last.first,
        scanned: batch.size,
        checked: ids.size,
        done: next_source.nil?,
      }
    end

    def self.sources_for(kind)
      case kind
      when 'public_statuses' then PUBLIC_SOURCES
      when 'statuses' then STATUS_SOURCES
      else raise ArgumentError, 'Invalid Nori sweep kind'
      end
    end

    def self.public_rows(after_id, batch_size)
      Status.unscoped.kept.indexable
        .where('statuses.id > ?', after_id)
        .reorder(id: :asc)
        .limit(batch_size + 1)
        .pluck(:id)
        .map { |id| [id, id] }
    end

    def self.status_rows(phase, after_id, batch_size)
      scope = StatusesBackfill.source_scope(phase)
      source_id = scope.klass.arel_table[:id]
      records = scope.where(source_id.gt(after_id)).distinct.reorder(source_id.asc).limit(batch_size + 1).to_a
      records.map { |record| [record.id, record.status_id] }
    end

    def self.index_rows(client, name, after_id, batch_size)
      body = {
        size: batch_size + 1,
        query: { match_all: {} },
        sort: [{ id: { order: 'asc' } }],
        _source: false,
        track_total_hits: false,
      }
      body[:search_after] = [after_id] if after_id.positive?

      response = client.search(index: name, body: body).body
      hits = response.dig('hits', 'hits')
      shards = response['_shards']
      valid = response['timed_out'] == false && shards.is_a?(Hash) &&
              shards['failed'].zero? && hits.is_a?(Array)
      raise InvalidResponse, "Incomplete Elasticsearch scan: #{name}" unless valid

      last_id = after_id
      hits.map do |hit|
        sort = hit['sort']
        id = sort.first if sort.is_a?(Array) && sort.size == 1
        valid_hit = id.is_a?(Integer) && id > last_id &&
                    hit['_id'] == id.to_s && hit['_index'] == name
        raise InvalidResponse, "Invalid Elasticsearch document ID: #{name}" unless valid_hit

        last_id = id
        [id, id]
      end
    end
  end
end
