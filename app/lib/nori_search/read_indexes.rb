# frozen_string_literal: true

module NoriSearch
  module ReadIndexes
    def self.enabled?
      ENV['ES_NORI_READ_ENABLED'] == 'true' &&
        ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true'
    end

    class StatusesIndex < ::StatusesIndex
      def self.index_name
        ::StatusesIndex.index_name(suffix: NoriSearch::ShadowImporter::SUFFIX)
      end
    end

    class PublicStatusesIndex < ::PublicStatusesIndex
      def self.index_name
        ::PublicStatusesIndex.index_name(suffix: NoriSearch::ShadowImporter::SUFFIX)
      end
    end
  end
end
