# frozen_string_literal: true

class PublicStatusesIndex < Chewy::Index
  include DatetimeClampingConcern

  korean_search_enabled = ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true'

  analysis_settings = {
    filter: {
      english_stop: {
        type: 'stop',
        stopwords: '_english_',
      },

      english_stemmer: {
        type: 'stemmer',
        language: 'english',
      },

      english_possessive_stemmer: {
        type: 'stemmer',
        language: 'possessive_english',
      },
    },

    tokenizer: {
      korean_custom: {
        type: 'nori_tokenizer',
        decompound_mode: 'mixed',
        user_dictionary_rules: [
          '겨자별',
          '연합우주 연합 우주',
        ],
      },
    },

    analyzer: {
      verbatim: {
        tokenizer: 'uax_url_email',
        filter: %w(lowercase),
      },

      content: {
        tokenizer: 'standard',
        filter: %w(
          lowercase
          asciifolding
          cjk_width
          elision
          english_possessive_stemmer
          english_stop
          english_stemmer
        ),
      },

      korean: {
        tokenizer: 'korean_custom',
        filter: %w(
          nori_part_of_speech
          nori_readingform
          lowercase
        ),
      },

      hashtag: {
        tokenizer: 'keyword',
        filter: %w(
          word_delimiter_graph
          lowercase
          asciifolding
          cjk_width
        ),
      },
    },
  }

  unless korean_search_enabled
    analysis_settings.delete(:tokenizer)
    analysis_settings[:analyzer].delete(:korean)
  end

  settings index: index_preset(refresh_interval: '30s', number_of_shards: 5), analysis: analysis_settings

  index_scope ::Status.unscoped
    .kept
    .indexable
    .includes(:media_attachments, :preloadable_poll, :tags, preview_cards_status: :preview_card)

  root date_detection: false do
    field(:id, type: 'long')
    field(:account_id, type: 'long')
    field(:text, type: 'text', analyzer: 'verbatim', value: ->(status) { status.searchable_text }) do
      field(:stemmed, type: 'text', analyzer: 'content')
      field(:korean, type: 'text', analyzer: 'korean') if korean_search_enabled
    end
    field(:tags, type: 'text', analyzer: 'hashtag', value: ->(status) { status.tags.map(&:display_name) })
    field(:language, type: 'keyword')
    field(:properties, type: 'keyword', value: ->(status) { status.searchable_properties })
    field(:created_at, type: 'date', value: ->(status) { clamp_date(status.created_at) })
  end
end
