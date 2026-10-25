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

  def expect_documents(index_class, ids, present:)
    [
      index_class.index_name,
      index_class.index_name(suffix: 'nori_v1'),
    ].each do |name|
      client.indices.refresh(index: name)
      results = ids.map { |id| client.exists?(index: name, id: id) }

      expect(results).to all(eq(present))
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
    expect(status).to be_persisted

    account.add_to_public_statuses_index!

    expect(indexed?(PublicStatusesIndex.index_name)).to be true
    expect(indexed?(PublicStatusesIndex.index_name(suffix: 'nori_v1'))).to be true

    account.update!(indexable: false)
    RemoveFromPublicStatusesIndexWorker.new.perform(account.id)

    expect(indexed?(PublicStatusesIndex.index_name)).to be false
    expect(indexed?(PublicStatusesIndex.index_name(suffix: 'nori_v1'))).to be false
  end

  it 'removes batched-deleted statuses from both index generations' do
    statuses = [status, Fabricate(:status, account: account, visibility: :public)]
    ids = statuses.map(&:id)

    [StatusesIndex, PublicStatusesIndex].each do |index_class|
      index_class.import!(ids)
      NoriSearch::ShadowImporter.import!(index_class, ids)
      expect_documents(index_class, ids, present: true)
    end

    Chewy.strategy(:mastodon) do
      BatchedRemoveStatusService.new.call(statuses, skip_side_effects: true)
    end

    expect(Status.unscoped.where(id: ids)).to be_empty

    [StatusesIndex, PublicStatusesIndex].each do |index_class|
      key = "chewy:queue:#{index_class.name}"
      expect(redis.smembers(key)).to include(*ids.map(&:to_s))
    end

    Scheduler::IndexingScheduler.new.perform

    [StatusesIndex, PublicStatusesIndex].each do |index_class|
      expect_documents(index_class, ids, present: false)
    end
  end

  it 'does not resurrect revoked public documents from delayed indexing' do
    expect(status).to be_persisted

    account.add_to_public_statuses_index!
    expect_documents(PublicStatusesIndex, [status.id], present: true)

    account.update!(indexable: false)
    RemoveFromPublicStatusesIndexWorker.new.perform(account.id)

    expect_documents(PublicStatusesIndex, [status.id], present: false)

    key = "chewy:queue:#{PublicStatusesIndex.name}"
    redis.sadd(key, status.id.to_s)

    expect(redis.sismember(key, status.id.to_s)).to be true

    Scheduler::IndexingScheduler.new.perform

    expect_documents(PublicStatusesIndex, [status.id], present: false)
    expect(redis.sismember(key, status.id.to_s)).to be false
  end

  it 'does not resurrect permanently deleted statuses from delayed indexing' do
    id = status.id

    [StatusesIndex, PublicStatusesIndex].each do |index_class|
      index_class.import!([id])
      NoriSearch::ShadowImporter.import!(index_class, [id])
      expect_documents(index_class, [id], present: true)
    end

    expect(Status.unscoped.where(id: id).delete_all).to eq(1)
    expect(Status.unscoped.exists?(id)).to be false

    [StatusesIndex, PublicStatusesIndex].each do |index_class|
      key = "chewy:queue:#{index_class.name}"
      redis.sadd(key, id.to_s)
      expect(redis.sismember(key, id.to_s)).to be true
    end

    Scheduler::IndexingScheduler.new.perform

    [StatusesIndex, PublicStatusesIndex].each do |index_class|
      expect_documents(index_class, [id], present: false)
      expect(redis.sismember("chewy:queue:#{index_class.name}", id.to_s)).to be false
    end
  end

  it 'removes expired remote statuses from both index generations after vacuum' do
    remote_account = Fabricate(:remote_account)
    old_remote = Fabricate(:status, account: remote_account, created_at: 9.days.ago)
    recent_remote = Fabricate(:status, account: remote_account, created_at: 5.days.ago)
    old_local = Fabricate(:status, account: account, created_at: 9.days.ago)

    Fabricate(:mention, account: account, status: old_remote)
    Fabricate(:mention, account: account, status: recent_remote)

    survivors = [recent_remote.id, old_local.id]
    ids = [old_remote.id, *survivors]

    [StatusesIndex, PublicStatusesIndex].each do |index_class|
      index_class.import!(ids)
      NoriSearch::ShadowImporter.import!(index_class, ids)
      expect_documents(index_class, ids, present: true)
    end

    Vacuum::StatusesVacuum.new(7.days).perform

    expect(Status.unscoped.exists?(old_remote.id)).to be false
    expect(Status.unscoped.where(id: survivors).count).to eq(2)

    [StatusesIndex, PublicStatusesIndex].each do |index_class|
      key = "chewy:queue:#{index_class.name}"
      expect(redis.sismember(key, old_remote.id.to_s)).to be true
    end

    Scheduler::IndexingScheduler.new.perform

    [StatusesIndex, PublicStatusesIndex].each do |index_class|
      expect_documents(index_class, [old_remote.id], present: false)
      expect_documents(index_class, survivors, present: true)

      key = "chewy:queue:#{index_class.name}"
      expect(redis.sismember(key, old_remote.id.to_s)).to be false
    end
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
