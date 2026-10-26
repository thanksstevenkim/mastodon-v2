# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Nori statuses backfill', :search do # rubocop:disable RSpec/DescribeClass
  let(:client) { Chewy.client }

  around do |example|
    ClimateControl.modify(ES_NORI_SHADOW_WRITES_ENABLED: 'true') { example.run }
  end

  before do
    skip 'Nori integration is disabled' unless ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true'

    StatusesIndex.create! unless StatusesIndex.exists?
    StatusesIndex.create!('nori_v1', alias: false) unless StatusesIndex.exists?('nori_v1')
  end

  after do
    StatusesIndex.delete('nori_v1') if StatusesIndex.exists?('nori_v1')
  end

  def legacy_snapshot(ids)
    name = StatusesIndex.index_name
    client.indices.refresh(index: name)

    ids.to_h do |id|
      document = (client.get(index: name, id: id).body['_source'] if client.exists?(index: name, id: id))

      [id, document]
    end
  end

  def nori_source(id)
    name = StatusesIndex.index_name(suffix: 'nori_v1')
    client.indices.refresh(index: name)
    client.get(index: name, id: id).body.fetch('_source')
  end

  it 'resumes across local posts and mentions without changing the legacy index' do
    local_account = Fabricate(:account)
    first = Fabricate(:status, account: local_account, visibility: :public)
    second = Fabricate(:status, account: local_account, visibility: :private)
    remote_account = Fabricate(:remote_account)
    mentioned = Fabricate(:status, account: remote_account, visibility: :public)
    Fabricate(:mention, account: local_account, status: mentioned)

    ids = [first.id, second.id, mentioned.id]
    legacy_before = legacy_snapshot(ids)

    first_result = NoriSearch::StatusesBackfill.run!(phase: 'local_statuses', after_id: 0, batch_size: 1)

    expect(first_result).to eq(phase: 'local_statuses', after_id: first.id, processed: 1, done: false)
    expect(nori_source(first.id).fetch('searchable_by')).to include(local_account.id)

    second_result = NoriSearch::StatusesBackfill.run!(
      phase: first_result[:phase], after_id: first_result[:after_id], batch_size: 1
    )

    expect(second_result).to eq(phase: 'local_mentions', after_id: 0, processed: 1, done: false)
    expect(nori_source(second.id).fetch('searchable_by')).to include(local_account.id)

    mention_result = NoriSearch::StatusesBackfill.run!(
      phase: second_result[:phase], after_id: second_result[:after_id], batch_size: 1
    )

    expect(mention_result).to eq(phase: 'local_favourites', after_id: 0, processed: 1, done: false)
    expect(nori_source(mentioned.id).fetch('searchable_by')).to include(local_account.id)
    expect(legacy_snapshot(ids)).to eq(legacy_before)
  end
end
