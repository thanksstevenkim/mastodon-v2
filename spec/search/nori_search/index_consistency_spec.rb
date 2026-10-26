# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NoriSearch::IndexConsistency, :search do
  let(:client) { Chewy.client }

  around do |example|
    ClimateControl.modify(ES_NORI_SHADOW_WRITES_ENABLED: 'true') { example.run }
  end

  before do
    skip 'Nori integration is disabled' unless ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true'

    [PublicStatusesIndex, StatusesIndex].each do |index_class|
      index_class.create! unless index_class.exists?
      index_class.create!('nori_v1', alias: false) unless index_class.exists?('nori_v1')
    end
  end

  after do
    [PublicStatusesIndex, StatusesIndex].each do |index_class|
      index_class.delete('nori_v1') if index_class.exists?('nori_v1')
    end
  end

  def populate(index_class, status)
    index_class.import!([status.id])
    index_class.import!([status.id], suffix: 'nori_v1')
    [index_class.index_name, index_class.index_name(suffix: 'nori_v1')].each do |name|
      client.indices.refresh(index: name)
    end
  end

  def issues_for(kind, id)
    described_class.verify!(kind: kind, ids: [id])
    nil
  rescue described_class::Mismatch => e
    e.issues.fetch(id.to_s)
  end

  it 'detects missing and revoked public documents' do
    account = Fabricate(:account, indexable: true)
    status = Fabricate(:status, account: account, visibility: :public)
    populate(PublicStatusesIndex, status)
    expect(described_class.verify!(kind: 'public_statuses', ids: [status.id])).to eq(kind: 'public_statuses', checked: 1)

    nori_name = PublicStatusesIndex.index_name(suffix: 'nori_v1')
    client.delete(index: nori_name, id: status.id, refresh: true)
    expect(issues_for('public_statuses', status.id)).to include('nori_missing')

    PublicStatusesIndex.import!([status.id], suffix: 'nori_v1')
    client.indices.refresh(index: nori_name)
    account.update!(indexable: false)
    expect(issues_for('public_statuses', status.id)).to include('nori_unexpected')
  end

  it 'detects a private-search ACL mismatch against the database' do
    account = Fabricate(:account)
    status = Fabricate(:status, account: account, visibility: :private)
    populate(StatusesIndex, status)
    expect(described_class.verify!(kind: 'statuses', ids: [status.id])).to eq(kind: 'statuses', checked: 1)

    nori_name = StatusesIndex.index_name(suffix: 'nori_v1')
    document = client.get(index: nori_name, id: status.id).body.fetch('_source')
    client.index(index: nori_name, id: status.id, body: document.merge('searchable_by' => []), refresh: true)

    expect(issues_for('statuses', status.id)).to include('nori_acl_mismatch')
  end
end
