# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Nori public statuses backfill', :search do # rubocop:disable RSpec/DescribeClass
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

  def indexed?(id, suffix: nil)
    name = suffix ? PublicStatusesIndex.index_name(suffix: suffix) : PublicStatusesIndex.index_name

    client.indices.refresh(index: name)
    client.exists?(index: name, id: id)
  end

  def legacy_snapshot(ids)
    name = PublicStatusesIndex.index_name
    client.indices.refresh(index: name)

    ids.to_h do |id|
      document = if client.exists?(index: name, id: id)
                   client.get(index: name, id: id).body['_source']
                 end

      [id, document]
    end
  end

  it 'backfills bounded Nori-only batches and resumes without indexing revoked accounts' do
    account = Fabricate(:account, indexable: true)
    first = Fabricate(:status, account: account, visibility: :public)
    second = Fabricate(:status, account: account, visibility: :public)

    revoked = Fabricate(:account, indexable: false)
    excluded = Fabricate(:status, account: revoked, visibility: :public)

    legacy_ids = [first.id, second.id, excluded.id]
    legacy_before = legacy_snapshot(legacy_ids)

    first_result = NoriSearch::PublicStatusesBackfill.run!(after_id: 0, batch_size: 1)

    expect(first_result).to eq(after_id: first.id, processed: 1, done: false)
    expect(indexed?(first.id, suffix: 'nori_v1')).to be true
    expect(indexed?(second.id, suffix: 'nori_v1')).to be false
    expect(legacy_snapshot(legacy_ids)).to eq(legacy_before)

    second_result = NoriSearch::PublicStatusesBackfill.run!(
      after_id: first_result[:after_id],
      batch_size: 1
    )

    expect(second_result).to eq(after_id: second.id, processed: 1, done: true)
    expect(indexed?(second.id, suffix: 'nori_v1')).to be true
    expect(legacy_snapshot(legacy_ids)).to eq(legacy_before)
    expect(indexed?(excluded.id, suffix: 'nori_v1')).to be false
  end
end
