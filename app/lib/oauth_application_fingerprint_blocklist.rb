# frozen_string_literal: true

module OAuthApplicationFingerprintBlocklist
  module_function

  BLOCKED_REDIRECT_URIS = ['urn:ietf:wg:oauth:2.0:oob'].freeze
  BLOCKED_WEBSITE = 'https://example.com'
  BLOCKED_SCOPES = %w(read write).freeze

  def blocked?(redirect_uris:, website:, scopes:, confidential:)
    confidential &&
      normalize_values(redirect_uris) == BLOCKED_REDIRECT_URIS &&
      normalize_website(website) == BLOCKED_WEBSITE &&
      normalize_values(scopes) == BLOCKED_SCOPES
  end

  def blocked_application?(application)
    blocked?(
      redirect_uris: application.redirect_uris,
      website: application.website,
      scopes: application.scopes,
      confidential: application.confidential?
    )
  end

  def normalize_values(value)
    Array(value)
      .flat_map { |item| item.to_s.split }
      .reject(&:empty?)
      .uniq
      .sort
  end

  def normalize_website(value)
    value.to_s.strip.downcase.sub(%r{/+\z}, '')
  end
end
