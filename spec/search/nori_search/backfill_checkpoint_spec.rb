# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NoriSearch::BackfillCheckpoint, :search do
  around do |example|
    ClimateControl.modify(ES_NORI_SHADOW_WRITES_ENABLED: 'true') { example.run }
  end

  before do
    skip 'Nori integration is disabled' unless ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true'

    PublicStatusesIndex.create! unless PublicStatusesIndex.exists?
    PublicStatusesIndex.create!('nori_v1', alias: false) unless PublicStatusesIndex.exists?('nori_v1')
  end

  after do
    PublicStatusesIndex.delete('nori_v1') if PublicStatusesIndex.exists?('nori_v1')
  end

  it 'persists a successful cursor, preserves it on failure, and resumes' do
    first = Fabricate(:status, account: Fabricate(:account, indexable: true), visibility: :public)
    second = Fabricate(:status, account: first.account, visibility: :public)
    key = "#{described_class::KEY_PREFIX}:#{PublicStatusesIndex.index_name(suffix: 'nori_v1')}"

    first_result = described_class.step!(kind: 'public_statuses', batch_size: 1)
    expect(first_result).to eq(after_id: first.id, processed: 1, done: false)

    saved_before = RedisConnection.with { |redis| redis.get(key) }
    expect(JSON.parse(saved_before)).to include('after_id' => first.id, 'done' => false)

    fail_once = true
    allow(PublicStatusesIndex).to receive(:import!).and_wrap_original do |original, *args, **options|
      if fail_once
        fail_once = false
        raise IOError, 'Simulated Nori import failure'
      end

      original.call(*args, **options)
    end

    expect { described_class.step!(kind: 'public_statuses', batch_size: 1) }
      .to raise_error(IOError, 'Simulated Nori import failure')
    expect(RedisConnection.with { |redis| redis.get(key) }).to eq(saved_before)

    second_result = described_class.step!(kind: 'public_statuses', batch_size: 1)
    expect(second_result).to eq(after_id: second.id, processed: 1, done: true)
    expect(JSON.parse(RedisConnection.with { |redis| redis.get(key) })).to include('after_id' => second.id, 'done' => true)
  end
end
