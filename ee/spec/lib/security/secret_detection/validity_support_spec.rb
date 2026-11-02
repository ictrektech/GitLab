# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::ValiditySupport, feature_category: :secret_detection do
  describe '.state' do
    using RSpec::Parameterized::TableSyntax

    # One row per analyzer/support combination.
    where(:token_type, :source, :expected) do
      'AWS'                           | Security::SecretDetection::Scanners::GSS      | :supported
      'AWS'                           | Security::SecretDetection::Scanners::GITLEAKS | :supported
      'OpenAiProjectKey'              | Security::SecretDetection::Scanners::GSS      | :supported
      'OpenAiProjectKey'              | Security::SecretDetection::Scanners::GITLEAKS | :supported_elsewhere
      'gitlab_personal_access_token'  | Security::SecretDetection::Scanners::GSS      | :supported
      'no_such_vendor_token'          | Security::SecretDetection::Scanners::GSS      | :unsupported
      'no_such_vendor_token'          | Security::SecretDetection::Scanners::GITLEAKS | :unsupported
    end

    with_them do
      it 'derives the support state from both registries' do
        expect(described_class.state(token_type: token_type, source: source)).to eq(expected)
      end
    end
  end

  describe '.display_state' do
    using RSpec::Parameterized::TableSyntax

    # Maps the support state to a display string; the registry -> state mapping
    # it builds on is covered by the .state examples above.
    where(:support_state, :expected) do
      :unsupported         | 'no_vendor_support'
      :supported_elsewhere | 'not_checked_by_analyzer'
      :supported           | nil
    end

    with_them do
      it 'maps the support state to a display state' do
        allow(described_class).to receive(:state).and_return(support_state)

        expect(described_class.display_state(token_type: 'x', source: 'y')).to eq(expected)
      end
    end
  end

  describe '.enabled_targets' do
    it 'returns the union of both registries', :aggregate_failures do
      expect(described_class.enabled_targets('AWS'))
        .to match_array(Security::SecretDetection::Scanners::ALL)
      expect(described_class.enabled_targets('gitlab_personal_access_token'))
        .to match_array(Security::SecretDetection::Scanners::ALL)
      expect(described_class.enabled_targets('no_such_vendor_token')).to eq([])
    end
  end
end
