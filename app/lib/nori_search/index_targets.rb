# frozen_string_literal: true

module NoriSearch
  class IndexTargets
    SUPPORTED_INDEXES = %w(
      statuses
      public_statuses
    ).freeze

    attr_reader :legacy, :nori, :read_alias

    def initialize(base_name:, prefix: nil)
      name = base_name.to_s
      unless SUPPORTED_INDEXES.include?(name)
        raise ArgumentError, 'Unsupported search index'
      end

      prefix = prefix.to_s
      unless prefix.empty? || prefix.match?(/\A[a-z0-9][a-z0-9._-]*\z/)
        raise ArgumentError, 'Invalid index prefix'
      end

      root = [prefix, name].reject(&:empty?).join('_')

      @legacy = root
      @nori = "#{root}_nori_v1"
      @read_alias = "#{root}_active"

      freeze
    end

    def to_h
      {
        legacy: legacy,
        nori: nori,
        read_alias: read_alias,
      }
    end
  end
end
