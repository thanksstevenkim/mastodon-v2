# frozen_string_literal: true

require 'json'

module NoriSearch
  class SweepCheckpoint
    extend Redisable

    VERSION = 1
    KEY_PREFIX = 'nori:sweep:checkpoint:test:v1'

    class UnsafeEnvironment < StandardError; end
    class UnsafeTarget < StandardError; end
    class InvalidCheckpoint < StandardError; end
    class StaleIndex < StandardError; end
    class Conflict < StandardError; end
    class Complete < StandardError; end

    def self.step!(kind:, batch_size:)
      safe_environment = Rails.env.test? &&
                         ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true' &&
                         ShadowImporter.enabled?
      raise UnsafeEnvironment, 'Nori sweep checkpoints require an isolated test environment' unless safe_environment
      raise ArgumentError, 'Invalid batch size' unless batch_size.is_a?(Integer) && batch_size.between?(1, IndexSweep::MAX_BATCH_SIZE)

      index_class = BackfillCheckpoint.index_for(kind)
      targets = IndexTargets.new(base_name: index_class.base_name, prefix: index_class.prefix)
      valid_target = index_class.index_name == targets.legacy &&
                     index_class.index_name(suffix: ShadowImporter::SUFFIX) == targets.nori
      raise ShadowImporter::UnexpectedTarget, 'Nori index name mismatch' unless valid_target

      client = index_class.client
      initial_uuids = index_uuids!(client, targets)
      key = "#{KEY_PREFIX}:#{targets.nori}"
      previous = with_redis { |redis| redis.get(key) }
      state = parse(previous, kind, initial_uuids)
      raise Complete, 'Nori consistency sweep already completed' if state.fetch('done')

      outcome = IndexSweep.step!(
        kind: kind,
        source: state.fetch('source'),
        after_id: state.fetch('after_id'),
        batch_size: batch_size
      )

      raise StaleIndex, 'Index generation changed during consistency sweep' unless index_uuids!(client, targets) == initial_uuids

      updated = state.merge(
        'source' => outcome.fetch(:source),
        'after_id' => outcome.fetch(:after_id),
        'done' => outcome.fetch(:done)
      )

      committed = with_redis do |redis|
        redis.watch(key) do
          raise Conflict, 'Nori sweep checkpoint changed concurrently' unless redis.get(key) == previous

          redis.multi { |transaction| transaction.set(key, JSON.generate(updated)) }
        end
      end
      raise Conflict, 'Nori sweep checkpoint transaction aborted' if committed.nil?

      outcome
    end

    def self.index_uuids!(client, targets)
      { legacy: targets.legacy, nori: targets.nori }.transform_values do |name|
        resolved = client.indices.get(index: name).body
        raise UnsafeTarget, "Not a concrete index: #{name}" unless resolved.keys == [name]

        settings = client.indices.get_settings(index: name).body
        uuid = settings.dig(name, 'settings', 'index', 'uuid')
        raise StaleIndex, "Index UUID unavailable: #{name}" unless uuid.is_a?(String) && uuid.present?

        uuid
      end
    end

    def self.parse(raw, kind, uuids)
      if raw.nil?
        return {
          'version' => VERSION,
          'kind' => kind,
          'legacy_uuid' => uuids.fetch(:legacy),
          'nori_uuid' => uuids.fetch(:nori),
          'source' => IndexSweep.sources_for(kind).first,
          'after_id' => 0,
          'done' => false,
        }
      end

      state = JSON.parse(raw)
      raise InvalidCheckpoint, 'Nori sweep checkpoint is not an object' unless state.is_a?(Hash)

      valid = state.keys.sort == %w(after_id done kind legacy_uuid nori_uuid source version) &&
              state['version'] == VERSION && state['kind'] == kind &&
              state['after_id'].is_a?(Integer) && state['after_id'] >= 0 &&
              [true, false].include?(state['done']) &&
              (state['done'] ? state['source'].nil? && state['after_id'].zero? : IndexSweep.sources_for(kind).include?(state['source']))
      raise InvalidCheckpoint, 'Invalid Nori sweep checkpoint state' unless valid

      matching = state['legacy_uuid'] == uuids.fetch(:legacy) && state['nori_uuid'] == uuids.fetch(:nori)
      raise StaleIndex, 'Index generation changed; sweep checkpoint cannot be reused' unless matching

      state
    rescue JSON::ParserError
      raise InvalidCheckpoint, 'Malformed Nori sweep checkpoint JSON'
    end
  end
end
