# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NoriSearch::SweepCheckpoint, :search do
  let(:nori_name) { PublicStatusesIndex.index_name(suffix: 'nori_v1') }
  let(:key) { "#{described_class::KEY_PREFIX}:#{nori_name}" }

  around do |example|
    ClimateControl.modify(ES_NORI_SHADOW_WRITES_ENABLED: 'true') { example.run }
  end

  before do
    skip 'Nori integration is disabled' unless ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true'

    PublicStatusesIndex.create! unless PublicStatusesIndex.exists?
    PublicStatusesIndex.create!('nori_v1', alias: false) unless PublicStatusesIndex.exists?('nori_v1')
    RedisConnection.with { |redis| redis.del(key) }
  end

  after do
    RedisConnection.with { |redis| redis.del(key) }
    PublicStatusesIndex.delete('nori_v1') if PublicStatusesIndex.exists?('nori_v1')
  end

  def checkpoint
    RedisConnection.with { |redis| redis.get(key) }
  end

  it 'persists a passing cursor, preserves it on failure, and resumes' do
    first = { source: 'legacy', after_id: 0, scanned: 1, checked: 1, done: false }
    allow(NoriSearch::IndexSweep).to receive(:step!).and_return(first)
    expect(described_class.step!(kind: 'public_statuses', batch_size: 1)).to eq(first)

    saved = checkpoint
    expect(JSON.parse(saved)).to include('source' => 'legacy', 'after_id' => 0, 'done' => false)

    allow(NoriSearch::IndexSweep).to receive(:step!).and_raise(IOError, 'Simulated sweep failure')
    expect { described_class.step!(kind: 'public_statuses', batch_size: 1) }.to raise_error(IOError, 'Simulated sweep failure')
    expect(checkpoint).to eq(saved)

    following = { source: 'nori', after_id: 0, scanned: 1, checked: 1, done: false }
    allow(NoriSearch::IndexSweep).to receive(:step!).with(kind: 'public_statuses', source: 'legacy', after_id: 0, batch_size: 1).and_return(following)
    expect(described_class.step!(kind: 'public_statuses', batch_size: 1)).to eq(following)
    expect(NoriSearch::IndexSweep).to have_received(:step!).with(kind: 'public_statuses', source: 'legacy', after_id: 0, batch_size: 1)
  end

  it 'rejects a checkpoint bound to a recreated Nori index' do
    first = { source: 'legacy', after_id: 0, scanned: 0, checked: 0, done: false }
    allow(NoriSearch::IndexSweep).to receive(:step!).and_return(first)
    described_class.step!(kind: 'public_statuses', batch_size: 1)
    saved = checkpoint

    PublicStatusesIndex.delete('nori_v1')
    PublicStatusesIndex.create!('nori_v1', alias: false)

    expect { described_class.step!(kind: 'public_statuses', batch_size: 1) }.to raise_error(described_class::StaleIndex)
    expect(checkpoint).to eq(saved)
  end
end
