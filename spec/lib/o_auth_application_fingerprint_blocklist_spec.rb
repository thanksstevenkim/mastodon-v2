# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OAuthApplicationFingerprintBlocklist do
  describe '.blocked?' do
    it 'blocks the observed automated-registration fingerprint' do
      expect(
        described_class.blocked?(
          redirect_uris: ['urn:ietf:wg:oauth:2.0:oob'],
          website: 'https://example.com',
          scopes: 'read write',
          confidential: true
        )
      ).to be true
    end

    it 'normalizes scope order, duplicate values, and a trailing website slash' do
      expect(
        described_class.blocked?(
          redirect_uris: 'urn:ietf:wg:oauth:2.0:oob',
          website: 'https://example.com/',
          scopes: 'write read read',
          confidential: true
        )
      ).to be true
    end

    it 'allows a different website' do
      expect(
        described_class.blocked?(
          redirect_uris: ['urn:ietf:wg:oauth:2.0:oob'],
          website: 'https://example.org',
          scopes: 'read write',
          confidential: true
        )
      ).to be false
    end

    it 'allows different scopes' do
      expect(
        described_class.blocked?(
          redirect_uris: ['urn:ietf:wg:oauth:2.0:oob'],
          website: 'https://example.com',
          scopes: 'read write follow',
          confidential: true
        )
      ).to be false
    end

    it 'allows a different redirect URI' do
      expect(
        described_class.blocked?(
          redirect_uris: ['https://client.example/callback'],
          website: 'https://example.com',
          scopes: 'read write',
          confidential: true
        )
      ).to be false
    end

    it 'allows a non-confidential application' do
      expect(
        described_class.blocked?(
          redirect_uris: ['urn:ietf:wg:oauth:2.0:oob'],
          website: 'https://example.com',
          scopes: 'read write',
          confidential: false
        )
      ).to be false
    end
  end

  describe '.blocked_application?' do
    it 'checks an existing OAuth application using the same fingerprint rules' do
      application = Fabricate(
        :application,
        redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
        website: 'https://example.com',
        scopes: 'read write',
        confidential: true
      )

      expect(described_class.blocked_application?(application)).to be true
    end
  end
end
