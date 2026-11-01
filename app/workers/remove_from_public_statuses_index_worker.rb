# frozen_string_literal: true

class RemoveFromPublicStatusesIndexWorker
  include Sidekiq::Worker

  def perform(account_id)
    account = Account.find(account_id)

    return if account.indexable?

    account.remove_from_public_statuses_index!
  rescue ActiveRecord::RecordNotFound
    return true unless Chewy.enabled?

    PublicStatusesIndex.filter(
      term: { account_id: account_id }
    ).delete_all

    NoriSearch::ShadowImporter.remove_public_account!(account_id)
  end
end
