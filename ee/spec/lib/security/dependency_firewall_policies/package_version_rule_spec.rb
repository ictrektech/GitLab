# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Security::DependencyFirewallPolicies::PackageVersionRule, feature_category: :dependency_firewall do
  let(:denied_rule) do
    {
      type: "package_version",
      denied: [{ name: 'lodash', version: '4.17.20' }]
    }
  end

  let(:license_rule) do
    {
      type: "license",
      denied: [{ name: 'MIT' }],
      allowed: [],
      exceptions: []
    }
  end

  describe '#evaluate' do
    let(:rule) { denied_rule }

    subject { described_class.new(rule).evaluate(package) }

    context 'when rule is not a package_version rule' do
      let(:rule) { license_rule }
      let(:package) { { name: 'lodash', purl_type: 'npm', version: '4.17.20' } }

      it { is_expected.to be_nil }
    end

    context 'when the package name and version match the denied entry' do
      let(:package) { { name: 'lodash', purl_type: 'npm', version: '4.17.20' } }

      it { is_expected.to eq({ action: :denied, reason: :evaluation }) }
    end

    context 'when the package name matches but the version does not' do
      let(:package) { { name: 'lodash', purl_type: 'npm', version: '4.17.21' } }

      it { is_expected.to eq({ action: :allowed, reason: :evaluation }) }
    end

    context 'when the package name does not match' do
      let(:package) { { name: 'express', purl_type: 'npm', version: '4.17.20' } }

      it { is_expected.to eq({ action: :allowed, reason: :evaluation }) }
    end

    context 'when the package has no version' do
      let(:package) { { name: 'lodash', purl_type: 'npm', version: nil } }

      it { is_expected.to eq({ action: :allowed, reason: :evaluation }) }
    end

    context 'when the package purl_type differs from the rule entry' do
      let(:package) { { name: 'lodash', purl_type: 'pypi', version: '4.17.20' } }

      it { is_expected.to eq({ action: :denied, reason: :evaluation }) }
    end

    context 'when the rule has several denied entries' do
      let(:rule) do
        {
          type: "package_version",
          denied: [{ name: 'express', version: '4.0.0' }, { name: 'lodash', version: '4.17.20' }]
        }
      end

      let(:package) { { name: 'lodash', purl_type: 'npm', version: '4.17.20' } }

      it { is_expected.to eq({ action: :denied, reason: :evaluation }) }
    end

    context 'when the matching denied entry has a reason and a reference link' do
      let(:rule) do
        {
          type: "package_version",
          denied: [
            { name: 'lodash', version: '4.17.20', reason: 'CVE-123', reference_link: 'https://example.com/CVE-123' }
          ]
        }
      end

      let(:package) { { name: 'lodash', purl_type: 'npm', version: '4.17.20' } }

      it 'returns only the reason in the details' do
        is_expected.to eq({ action: :denied, reason: :evaluation, details: { reason: 'CVE-123' } })
      end
    end

    context 'when several denied entries each have their own reason' do
      let(:rule) do
        {
          type: "package_version",
          denied: [
            { name: 'lodash', version: '4.17.20', reason: 'CVE-123' },
            { name: 'redis', version: '4.35.09', reason: 'CVE-321' }
          ]
        }
      end

      let(:package) { { name: 'redis', purl_type: 'npm', version: '4.35.09' } }

      it 'returns the reason of the matching entry' do
        is_expected.to eq({ action: :denied, reason: :evaluation, details: { reason: 'CVE-321' } })
      end
    end

    context 'when the version differs from the entry that has a reason' do
      let(:rule) do
        {
          type: "package_version",
          denied: [{ name: 'lodash', version: '4.17.20', reason: 'CVE-123' }]
        }
      end

      let(:package) { { name: 'lodash', purl_type: 'npm', version: '4.17.21' } }

      it { is_expected.to eq({ action: :allowed, reason: :evaluation }) }
    end

    context 'when the rule has no denied entries' do
      let(:rule) { { type: "package_version" } }
      let(:package) { { name: 'lodash', purl_type: 'npm', version: '4.17.20' } }

      it { is_expected.to eq({ action: :allowed, reason: :evaluation }) }
    end
  end
end
