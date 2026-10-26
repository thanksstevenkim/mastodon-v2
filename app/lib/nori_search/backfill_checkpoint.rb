# frozen_string_literal: true

require 'json'

module NoriSearch
  class BackfillCheckpoint
    extend Redisable

    VERSION = 1
    KEY_PREFIX = 'nori:backfill:checkpoint:test:v1'

    class UnsafeEnvironment < StandardError; end
    class InvalidCheckpoint < StandardError; end
    class StaleIndex < StandardError; end
    class Conflict < StandardError; end
    class Complete < StandardError; end

    def self.step!(kind:, batch_size:)
      safe_environment = Rails.env.test? &&
                         ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true' &&
                         ShadowImporter.enabled?
      raise UnsafeEnvironment, 'Nori checkpoints require an isolated test environment' unless safe_environment

      index_class = index_for(kind)
      targets = IndexTargets.new(base_name: index_class.base_name, prefix: index_class.prefix)
      valid_target = index_class.index_name == targets.legacy &&
                     index_class.index_name(suffix: ShadowImporter::SUFFIX) == targets.nori
      raise ShadowImporter::UnexpectedTarget, 'Nori index name mismatch' unless valid_target
      raise ShadowImporter::MissingIndex, "Nori target unavailable: #{targets.nori}" unless index_class.client.indices.exists(index: targets.nori)

      settings = index_class.client.indices.get_settings(index: targets.nori)
      index_uuid = settings.dig(targets.nori, 'settings', 'index', 'uuid')
      raise StaleIndex, 'Nori index UUID unavailable' unless index_uuid.is_a?(String) && index_uuid.present?

      key = "#{KEY_PREFIX}:#{targets.nori}"
      old_raw = with_redis { |redis| redis.get(key) }
      state = parse(old_raw, kind, index_uuid)
      raise Complete, 'Nori backfill already completed' if state.fetch('done')

      outcome = if kind == 'public_statuses'
                  PublicStatusesBackfill.run!(after_id: state.fetch('after_id'), batch_size: batch_size)
                else
                  StatusesBackfill.run!(phase: state.fetch('phase'), after_id: state.fetch('after_id'), batch_size: batch_size)
                end

      updated = state.merge(
        'phase' => outcome[:phase],
        'after_id' => outcome.fetch(:after_id),
        'done' => outcome.fetch(:done)
      )

      committed = with_redis do |redis|
        redis.watch(key) do
          raise Conflict, 'Nori checkpoint changed concurrently' unless redis.get(key) == old_raw

          redis.multi { |transaction| transaction.set(key, JSON.generate(updated)) }
        end
      end
      raise Conflict, 'Nori checkpoint transaction aborted' if committed.nil?

      outcome
    end

    def self.index_for(kind)
      case kind
      when 'public_statuses' then PublicStatusesIndex
      when 'statuses' then StatusesIndex
      else raise ArgumentError, 'Invalid Nori backfill kind'
      end
    end

    def self.parse(raw, kind, index_uuid)
      if raw.nil?
        return {
          'version' => VERSION,
          'kind' => kind,
          'index_uuid' => index_uuid,
          'phase' => kind == 'statuses' ? StatusesBackfill::PHASES.first : nil,
          'after_id' => 0,
          'done' => false,
        }
      end

      state = JSON.parse(raw)
      raise InvalidCheckpoint, 'Nori checkpoint is not an object' unless state.is_a?(Hash)
      raise StaleIndex, 'Nori index was recreated; checkpoint cannot be reused' unless state['index_uuid'] == index_uuid

      valid_phase = if kind == 'statuses'
                      state['done'] == true ? state['phase'].nil? : StatusesBackfill::PHASES.include?(state['phase'])
                    else
                      state['phase'].nil?
                    end
      valid = state.keys.sort == %w(after_id done index_uuid kind phase version) &&
              state['version'] == VERSION && state['kind'] == kind &&
              state['after_id'].is_a?(Integer) && state['after_id'] >= 0 &&
              [true, false].include?(state['done']) && valid_phase
      raise InvalidCheckpoint, 'Invalid Nori checkpoint state' unless valid

      state
    rescue JSON::ParserError
      raise InvalidCheckpoint, 'Malformed Nori checkpoint JSON'
    end
  end
end
