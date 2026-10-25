# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NoriSearch::ShadowImporter do
  let(:ids) { %w(91001 91002) }
  let(:index_class) { StatusesIndex }

  it 'does not write when disabled' do
    ClimateControl.modify(ES_NORI_SHADOW_WRITES_ENABLED: nil) do
      allow(index_class).to receive(:import!)
      expect(described_class.import!(index_class, ids)).to be true
      expect(index_class).to_not have_received(:import!)
    end
  end

  it 'imports to the Nori suffix when enabled' do
    ClimateControl.modify(ES_NORI_SHADOW_WRITES_ENABLED: 'true') do
      indices = double(exists: true)
      allow(index_class).to receive(:client).and_return(double(indices: indices))

      allow(index_class).to receive(:import!)
        .with(ids, suffix: 'nori_v1')
        .and_return(true)

      expect(described_class.import!(index_class, ids)).to be true
      expect(index_class).to have_received(:import!).with(ids, suffix: 'nori_v1')
    end
  end

  it 'fails if the Nori index does not exist' do
    ClimateControl.modify(ES_NORI_SHADOW_WRITES_ENABLED: 'true') do
      indices = double(exists: false)
      allow(index_class).to receive(:client).and_return(double(indices: indices))

      allow(index_class).to receive(:import!)

      expect do
        described_class.import!(index_class, ids)
      end.to raise_error(described_class::MissingIndex)
      expect(index_class).to_not have_received(:import!)
    end
  end

  it 'leaves unrelated indices alone' do
    ClimateControl.modify(ES_NORI_SHADOW_WRITES_ENABLED: 'true') do
      allow(AccountsIndex).to receive(:import!)
      expect(described_class.import!(AccountsIndex, ids)).to be true
      expect(AccountsIndex).to_not have_received(:import!)
    end
  end

  describe '.remove_public_account!' do
    around do |example|
      ClimateControl.modify(
        ES_NORI_SHADOW_WRITES_ENABLED: 'true'
      ) { example.run }
    end

    let(:indices) { double(exists: true) }
    let(:client) { double(indices: indices) }

    before do
      allow(PublicStatusesIndex).to receive(:client)
        .and_return(client)
    end

    it 'deletes the account from the Nori index' do
      allow(client).to receive(:delete_by_query).with(
        index: 'public_statuses_nori_v1',
        body: {
          query: {
            term: { account_id: 2002 },
          },
        },
        refresh: true,
        conflicts: 'abort',
        wait_for_completion: true
      ).and_return(
        'timed_out' => false,
        'failures' => [],
        'version_conflicts' => 0
      )

      expect(described_class.remove_public_account!(2002)).to be true
      expect(client).to have_received(:delete_by_query)
    end

    it 'rejects incomplete deletion responses' do
      allow(client).to receive(:delete_by_query)
        .and_return(
          'timed_out' => true,
          'failures' => [],
          'version_conflicts' => 0
        )

      expect do
        described_class.remove_public_account!(2002)
      end.to raise_error(described_class::IncompleteDeletion)
    end

    it 'rejects invalid account IDs' do
      expect do
        described_class.remove_public_account!(-1)
      end.to raise_error(ArgumentError)
    end
  end
end
