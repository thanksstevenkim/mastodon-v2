# frozen_string_literal: true

require 'rails_helper'

# This integration spec covers both status indices, not a single class.
RSpec.describe 'Korean search integration' do # rubocop:disable RSpec/DescribeClass
  before do
    skip 'Nori integration is disabled' unless ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true'
  end

  [StatusesIndex, PublicStatusesIndex].each do |index_class|
    context "with #{index_class.name}" do
      before { index_class.create! }

      it 'creates the Korean field in the actual Elasticsearch mapping' do
        mapping = Chewy.client.indices.get_mapping(index: index_class.index_name)
        fields = mapping.dig(index_class.index_name, 'mappings', 'properties', 'text', 'fields')

        expect(fields.fetch('korean')).to include('type' => 'text', 'analyzer' => 'korean')
      end

      it 'keeps server-specific words in the Korean analyzer' do
        response = Chewy.client.indices.analyze(
          index: index_class.index_name,
          body: { field: 'text.korean', text: '겨자별에서 연합우주 이야기를 했어요' }
        )
        tokens = response.fetch('tokens').map { |token| token.fetch('token') }

        expect(tokens).to include('겨자별', '연합우주', '연합', '우주')
      end

      it 'finds a Korean base word in an inflected status' do
        Chewy.client.index(
          index: index_class.index_name,
          id: 'nori-match',
          body: { text: '마스토돈에서 한국어 검색을 개선하고 싶어요' }
        )
        Chewy.client.indices.refresh(index: index_class.index_name)

        query = SearchQueryTransformer::TermClause.new(nil, '마스토돈').to_query
        result = Chewy.client.search(index: index_class.index_name, body: { query: query })
        ids = result.dig('hits', 'hits').map { |hit| hit.fetch('_id') }

        expect(ids).to include('nori-match')
      end
    end
  end
end
