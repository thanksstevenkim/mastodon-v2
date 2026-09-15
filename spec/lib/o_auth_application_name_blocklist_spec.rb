# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OAuthApplicationNameBlocklist do
  describe '.blocked?' do
    around do |example|
      ClimateControl.modify BLOCKED_OAUTH_APP_NAMES: 'BoomProtocolProbe,BadClient' do
        example.run
      end
    end

    it 'blocks configured application names' do
      expect(described_class.blocked?('BoomProtocolProbe')).to be true
      expect(described_class.blocked?('BadClient')).to be true
    end

    it 'matches application names case-insensitively' do
      expect(described_class.blocked?('boomprotocolprobe')).to be true
    end

    it 'allows application names not on the blocklist' do
      expect(described_class.blocked?('Tusky')).to be false
    end
  end
end
