# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SearchQueryTransformer do
  subject { described_class.new.apply(parser, current_account: account) }

  let(:account) { Fabricate(:account) }
  let(:parser) { SearchQueryParser.new.parse(query) }

  shared_examples 'date operator' do |operator|
    let(:statement_operations) { [] }

    [
      ['2022-01-01', '2022-01-01'],
      ['"2022-01-01"', '2022-01-01'],
      ['12345678', '12345678'],
      ['"12345678"', '12345678'],
      ['"2024-10-31T23:47:20Z"', '2024-10-31T23:47:20Z'],
    ].each do |value, parsed|
      context "with #{operator}:#{value}" do
        let(:query) { "#{operator}:#{value}" }

        it 'transforms clauses' do
          ops = statement_operations.index_with { |_op| parsed }

          expect(subject.send(:must_clauses)).to be_empty
          expect(subject.send(:must_not_clauses)).to be_empty
          expect(subject.send(:filter_clauses).map(&:term)).to contain_exactly(**ops, time_zone: 'UTC')
        end
      end
    end

    context "with #{operator}:\"abc\"" do
      let(:query) { "#{operator}:\"abc\"" }

      it 'raises an exception' do
        expect { subject }.to raise_error(Date::Error)
      end
    end
  end

  context 'with "hello world"' do
    let(:query) { 'hello world' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to match_array %w(hello world)
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses)).to be_empty
    end
  end

  context 'with "hello -world"' do
    let(:query) { 'hello -world' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to match_array %w(hello)
      expect(subject.send(:must_not_clauses).map(&:term)).to match_array %w(world)
      expect(subject.send(:filter_clauses)).to be_empty
    end
  end

  context 'with "hello is:reply"' do
    let(:query) { 'hello is:reply' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to match_array %w(hello)
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses).map(&:term)).to match_array %w(reply)
    end
  end

  context 'with "foo: bar"' do
    let(:query) { 'foo: bar' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to match_array %w(foo bar)
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses)).to be_empty
    end
  end

  context 'with "foo:bar"' do
    let(:query) { 'foo:bar' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to contain_exactly('foo bar')
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses)).to be_empty
    end
  end

  context 'with \'"hello world"\'' do
    let(:query) { '"hello world"' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:phrase)).to contain_exactly('hello world')
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses)).to be_empty
    end
  end

  context 'with \'is:"foo bar"\'' do
    let(:query) { 'is:"foo bar"' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses)).to be_empty
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses).map(&:term)).to contain_exactly('foo bar')
    end
  end

  context 'with date operators' do
    context 'with "before"' do
      it_behaves_like 'date operator', 'before' do
        let(:statement_operations) { [:lt] }
      end
    end

    context 'with "after"' do
      it_behaves_like 'date operator', 'after' do
        let(:statement_operations) { [:gt] }
      end
    end

    context 'with "during"' do
      it_behaves_like 'date operator', 'during' do
        let(:statement_operations) { [:gte, :lte] }
      end
    end
  end

  context 'with multiple prefix clauses before a search term' do
    let(:query) { 'from:me has:media foo' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to contain_exactly('foo')
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses).map(&:prefix)).to contain_exactly('from', 'has')
    end
  end

  context 'with a search term between two prefix clauses' do
    let(:query) { 'from:me foo has:media' }

    it 'transforms clauses' do
      expect(subject.send(:must_clauses).map(&:term)).to contain_exactly('foo')
      expect(subject.send(:must_not_clauses)).to be_empty
      expect(subject.send(:filter_clauses).map(&:prefix)).to contain_exactly('from', 'has')
    end
  end

  describe 'Nori search queries' do
    around do |example|
      ClimateControl.modify(ES_KOREAN_SEARCH_ENABLED: 'true', ES_NORI_READ_ENABLED: 'true', ES_NORI_READ_CUTOVER_ENABLED: 'true') { example.run }
    end

    it 'preserves legacy fields when Nori is disabled' do
      ClimateControl.modify(ES_KOREAN_SEARCH_ENABLED: 'false') do
        fields = described_class::TermClause.new(nil, '마스토돈').to_query.dig(:multi_match, :fields)
        expect(fields).to eq(%w(text text.stemmed))
      end
    end

    it 'preserves legacy fields when the flag is unset' do
      ClimateControl.modify(ES_KOREAN_SEARCH_ENABLED: nil) do
        fields = described_class::TermClause.new(nil, '마스토돈').to_query.dig(:multi_match, :fields)
        expect(fields).to eq(%w(text text.stemmed))
      end
    end

    it 'includes the Korean field in normal term searches' do
      clause = described_class::TermClause.new(nil, '마스토돈')

      expect(clause.to_query).to eq(
        multi_match: {
          type: 'most_fields',
          query: '마스토돈',
          fields: %w(text text.stemmed text.korean),
          operator: 'and',
        }
      )
    end

    it 'preserves negative search operators' do
      clause = described_class::TermClause.new('-', '겨자별')

      expect(clause.operator).to eq(:must_not)
      expect(clause.to_query.dig(:multi_match, :fields))
        .to eq(%w(text text.stemmed text.korean))
    end

    it 'preserves hashtag search behavior' do
      clause = described_class::TermClause.new(nil, '#겨자별')

      expect(clause.to_query).to eq(
        match: {
          tags: {
            query: '#겨자별',
            operator: 'and',
          },
        }
      )
    end

    it 'preserves exact phrase search behavior' do
      clause = described_class::PhraseClause.new(nil, '겨자별 공지사항')

      expect(clause.to_query).to eq(
        match_phrase: {
          text: {
            query: '겨자별 공지사항',
          },
        }
      )
    end
  end

  describe 'Nori read index routing' do
    let(:query) { '마스토돈' }

    around do |example|
      ClimateControl.modify(ES_KOREAN_SEARCH_ENABLED: 'true', ES_NORI_READ_ENABLED: 'true', ES_NORI_READ_CUTOVER_ENABLED: 'true') { example.run }
    end

    it 'selects Nori concrete indices with the existing account permission filter' do
      expect(subject.send(:indexes).map(&:index_name)).to eq([
        PublicStatusesIndex.index_name(suffix: 'nori_v1'),
        StatusesIndex.index_name(suffix: 'nori_v1'),
      ])

      filters = subject.send(:default_filter).dig(:bool, :should)

      expect(filters[0].dig(:term, :_index)).to eq(PublicStatusesIndex.index_name(suffix: 'nori_v1'))
      expect(filters[1].dig(:bool, :must)[0].dig(:term, :_index)).to eq(StatusesIndex.index_name(suffix: 'nori_v1'))
      expect(filters[1].dig(:bool, :must)[1].dig(:term, :searchable_by)).to eq(account.id)
    end

    it 'preserves public and library search scopes' do
      public_query = described_class.new.apply(SearchQueryParser.new.parse('in:public 마스토돈'), current_account: account)
      library_query = described_class.new.apply(SearchQueryParser.new.parse('in:library 마스토돈'), current_account: account)

      expect(public_query.send(:indexes).map(&:index_name)).to eq([PublicStatusesIndex.index_name(suffix: 'nori_v1')])
      expect(library_query.send(:indexes).map(&:index_name)).to eq([StatusesIndex.index_name(suffix: 'nori_v1')])
    end

    it 'keeps legacy routing when cutover approval is absent' do
      ClimateControl.modify(ES_NORI_READ_CUTOVER_ENABLED: nil) do
        expect(subject.send(:indexes).map(&:index_name)).to eq([PublicStatusesIndex.index_name, StatusesIndex.index_name])
        expect(described_class::TermClause.new(nil, '마스토돈').to_query.dig(:multi_match, :fields)).to eq(%w(text text.stemmed))
      end
    end

    it 'keeps legacy routing when the read flag is disabled' do
      ClimateControl.modify(ES_NORI_READ_ENABLED: 'false') do
        expect(subject.send(:indexes).map(&:index_name)).to eq([PublicStatusesIndex.index_name, StatusesIndex.index_name])
      end
    end
  end
end
