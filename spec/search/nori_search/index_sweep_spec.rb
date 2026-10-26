# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NoriSearch::IndexSweep, :search do
  let(:client) { Chewy.client }

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

  def nori_name
    PublicStatusesIndex.index_name(suffix: 'nori_v1')
  end

  it 'advances the database cursor and detects a Nori document missing from that source' do
    status = Fabricate(:status, account: Fabricate(:account, indexable: true), visibility: :public)
    PublicStatusesIndex.import!([status.id])
    PublicStatusesIndex.import!([status.id], suffix: 'nori_v1')
    [PublicStatusesIndex.index_name, nori_name].each { |name| client.indices.refresh(index: name) }

    outcome = described_class.step!(kind: 'public_statuses', source: 'database', after_id: status.id - 1, batch_size: 1)
    expect(outcome).to eq(source: 'legacy', after_id: 0, scanned: 1, checked: 1, done: false)

    client.delete(index: nori_name, id: status.id, refresh: true)
    expect do
      described_class.step!(kind: 'public_statuses', source: 'database', after_id: status.id - 1, batch_size: 1)
    end.to raise_error(NoriSearch::IndexConsistency::Mismatch) { |error| expect(error.issues.fetch(status.id.to_s)).to include('nori_missing') }
  end

  it 'detects an orphan that exists only in the Nori index' do
    orphan_id = 9_000_000_000_000_000_000
    client.index(index: nori_name, id: orphan_id, body: { id: orphan_id, account_id: 0 }, refresh: true)

    expect do
      described_class.step!(kind: 'public_statuses', source: 'nori', after_id: orphan_id - 1, batch_size: 1)
    end.to raise_error(NoriSearch::IndexConsistency::Mismatch) { |error| expect(error.issues.fetch(orphan_id.to_s)).to include('nori_unexpected') }
  end
end
