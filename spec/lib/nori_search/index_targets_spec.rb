# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../app/lib/nori_search/index_targets'

RSpec.describe NoriSearch::IndexTargets do
  it 'provides distinct names for private search' do
    targets = described_class.new(base_name: 'statuses')

    expect(targets.to_h).to eq(
      legacy: 'statuses',
      nori: 'statuses_nori_v1',
      read_alias: 'statuses_active'
    )
  end

  it 'provides distinct names for public search' do
    targets = described_class.new(base_name: 'public_statuses')

    expect(targets.to_h).to eq(
      legacy: 'public_statuses',
      nori: 'public_statuses_nori_v1',
      read_alias: 'public_statuses_active'
    )
  end

  it 'supports index prefixes' do
    targets = described_class.new(
      base_name: 'statuses',
      prefix: 'lab'
    )

    expect(targets.legacy).to eq('lab_statuses')
    expect(targets.nori).to eq('lab_statuses_nori_v1')
    expect(targets.read_alias).to eq('lab_statuses_active')
  end

  it 'rejects unsupported indices' do
    expect do
      described_class.new(base_name: 'accounts')
    end.to raise_error(ArgumentError)
  end

  it 'rejects unsafe prefixes' do
    expect do
      described_class.new(
        base_name: 'statuses',
        prefix: '../unsafe'
      )
    end.to raise_error(ArgumentError)
  end
end
