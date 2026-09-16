# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignupReasonBlocklist do
  describe '.blocked?' do
    around do |example|
      ClimateControl.modify BLOCKED_SIGNUP_REASONS: 'Automated protocol deliverability probe,Bad signup reason' do
        example.run
      end
    end

    it 'blocks configured signup reasons' do
      expect(described_class.blocked?('Automated protocol deliverability probe')).to be true
      expect(described_class.blocked?('Bad signup reason')).to be true
    end

    it 'matches signup reasons case-insensitively' do
      expect(described_class.blocked?('automated protocol deliverability probe')).to be true
    end

    it 'allows signup reasons not on the blocklist' do
      expect(described_class.blocked?('I want to join this community')).to be false
    end
  end
end
