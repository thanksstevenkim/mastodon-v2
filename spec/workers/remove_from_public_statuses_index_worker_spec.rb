# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RemoveFromPublicStatusesIndexWorker do
  describe '#perform' do
    let(:account) { Fabricate(:account, indexable: indexable) }
    let(:account_id) { account.id }

    before do
      allow(Account).to receive(:find).with(account_id).and_return(account) unless account.nil?
      allow(account).to receive(:remove_from_public_statuses_index!) unless account.nil?
    end

    context 'when account is not indexable' do
      let(:indexable) { false }

      it 'removes the account from public statuses index' do
        subject.perform(account_id)
        expect(account).to have_received(:remove_from_public_statuses_index!)
      end
    end

    context 'when account is indexable' do
      let(:indexable) { true }

      it 'does not remove the account from public statuses index' do
        subject.perform(account_id)
        expect(account).to_not have_received(:remove_from_public_statuses_index!)
      end
    end

    context 'when account does not exist' do
      let(:account) { nil }
      let(:account_id) { 999 }

      before do
        allow(Account).to receive(:find)
          .with(account_id)
          .and_raise(ActiveRecord::RecordNotFound)
      end

      it 'does not access indices when Chewy is disabled' do
        allow(Chewy).to receive(:enabled?).and_return(false)

        allow(PublicStatusesIndex).to receive(:filter)
        allow(NoriSearch::ShadowImporter)
          .to receive(:remove_public_account!)

        expect { subject.perform(account_id) }.to_not raise_error
        expect(PublicStatusesIndex).to_not have_received(:filter)
        expect(NoriSearch::ShadowImporter).to_not have_received(:remove_public_account!)
      end

      it 'cleans up both index generations' do
        allow(Chewy).to receive(:enabled?).and_return(true)

        query = double
        allow(PublicStatusesIndex).to receive(:filter)
          .with(term: { account_id: account_id })
          .and_return(query)
        allow(query).to receive(:delete_all).and_return(true)

        allow(NoriSearch::ShadowImporter)
          .to receive(:remove_public_account!)
          .with(account_id)
          .and_return(true)

        subject.perform(account_id)

        expect(PublicStatusesIndex).to have_received(:filter)
          .with(term: { account_id: account_id })
        expect(query).to have_received(:delete_all)
        expect(NoriSearch::ShadowImporter)
          .to have_received(:remove_public_account!)
          .with(account_id)
      end

      it 'propagates a Nori deletion failure' do
        allow(Chewy).to receive(:enabled?).and_return(true)

        query = double(delete_all: true)
        allow(PublicStatusesIndex).to receive(:filter)
          .and_return(query)

        allow(NoriSearch::ShadowImporter)
          .to receive(:remove_public_account!)
          .with(account_id)
          .and_raise(
            NoriSearch::ShadowImporter::IncompleteDeletion
          )

        expect do
          subject.perform(account_id)
        end.to raise_error(
          NoriSearch::ShadowImporter::IncompleteDeletion
        )
      end
    end
  end
end
