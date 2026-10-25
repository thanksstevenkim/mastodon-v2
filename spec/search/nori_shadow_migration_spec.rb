# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Nori shadow migration integration', :search do # rubocop:disable RSpec/DescribeClass
  let(:client) { Chewy.client }
  let(:account) { Fabricate(:account, indexable: true) }
  let(:status) { Fabricate(:status, account: account, visibility: :public) }

  around do |example|
    ClimateControl.modify(ES_NORI_SHADOW_WRITES_ENABLED: 'true') do
      example.run
    end
  end

  before do
    skip 'Nori integration is disabled' unless ENV['ES_KOREAN_SEARCH_ENABLED'] == 'true'

    [StatusesIndex, PublicStatusesIndex].each do |index_class|
      index_class.create! unless index_class.exists?
      index_class.create!('nori_v1', alias: false) unless index_class.exists?('nori_v1')
    end
  end

  after do
    [StatusesIndex, PublicStatusesIndex].each do |index_class|
      index_class.delete('nori_v1') if index_class.exists?('nori_v1')
    end
  end

  def indexed?(index_name)
    client.indices.refresh(index: index_name)
    client.exists?(index: index_name, id: status.id)
  end

  it 'synchronizes queued status updates to both physical indices' do
    key = "chewy:queue:#{StatusesIndex.name}"
    redis.sadd(key, status.id.to_s)

    Scheduler::IndexingScheduler.new.perform

    expect(indexed?(StatusesIndex.index_name)).to be true
    expect(indexed?(StatusesIndex.index_name(suffix: 'nori_v1'))).to be true
    expect(redis.sismember(key, status.id.to_s)).to be false
  end

  it 'removes public status documents from both indices after revocation' do
    account.add_to_public_statuses_index!

    expect(indexed?(PublicStatusesIndex.index_name)).to be true
    expect(indexed?(PublicStatusesIndex.index_name(suffix: 'nori_v1'))).to be true

    account.update!(indexable: false)
    RemoveFromPublicStatusesIndexWorker.new.perform(account.id)

    expect(indexed?(PublicStatusesIndex.index_name)).to be false
    expect(indexed?(PublicStatusesIndex.index_name(suffix: 'nori_v1'))).to be false
  end

  it 'preserves the Redis queue when the Nori index is missing' do
    key = "chewy:queue:#{StatusesIndex.name}"
    redis.sadd(key, status.id.to_s)

    StatusesIndex.delete('nori_v1')

    expect do
      Scheduler::IndexingScheduler.new.perform
    end.to raise_error(NoriSearch::ShadowImporter::MissingIndex)

    expect(redis.sismember(key, status.id.to_s)).to be true
    expect(indexed?(StatusesIndex.index_name)).to be true
  end
end
