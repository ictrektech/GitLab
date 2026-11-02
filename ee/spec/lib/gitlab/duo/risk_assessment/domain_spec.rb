# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::RiskAssessment::Domain, feature_category: :dap_code_review do
  include I18nHelper

  def build_domain(**overrides)
    described_class.new(
      { id: 1, name: 'test_domain', severity: 'high', description: 'Test domain' }.merge(overrides)
    )
  end

  # The point of modelling domains as fixed items: an incomplete domain is
  # refused by validation rather than registering quietly and never being asked.
  describe 'validations' do
    it 'accepts a fully declared domain' do
      expect(build_domain).to be_valid
    end

    it 'requires a name' do
      expect(build_domain(name: nil)).to be_invalid
    end

    it 'requires a severity, so an omission cannot pass for a choice' do
      domain = build_domain(severity: nil)

      expect(domain).to be_invalid
      expect(domain.errors[:severity]).to be_present
    end

    it 'rejects an unknown severity' do
      domain = build_domain(severity: 'medium')

      expect(domain).to be_invalid
      expect(domain.errors[:severity]).to be_present
    end

    it 'requires a description' do
      expect(build_domain(description: nil)).to be_invalid
    end
  end

  describe '.registered_domains' do
    it 'registers the domains in the order their ids depend on' do
      expect(described_class.registered_domains).to eq(
        [
          Gitlab::Duo::RiskAssessment::Domains::Authorization,
          Gitlab::Duo::RiskAssessment::Domains::Authentication,
          Gitlab::Duo::RiskAssessment::Domains::DatabaseMigration,
          Gitlab::Duo::RiskAssessment::Domains::ApiContract,
          Gitlab::Duo::RiskAssessment::Domains::CredentialsCrypto
        ]
      )
    end
  end

  describe '.description_for' do
    it 'resolves the description of a registered domain' do
      expect(described_class.description_for('credentials_crypto'))
        .to eq('Cryptography, key management, or credential handling')
    end

    it 'returns the name for a name that is not a registered domain' do
      expect(described_class.description_for('diff_shape')).to eq('diff_shape')
    end

    it 'resolves the translated description when the locale is not English' do
      with_stubbed_translations(
        'de', { 'RiskAssessment|Cryptography, key management, or credential handling' => 'Kryptografie' }
      ) do
        expect(described_class.description_for('credentials_crypto')).to eq('Kryptografie')
      end
    end
  end

  describe '#description' do
    subject(:description) { domain.description }

    let(:english_description) { 'Authorization, access control, or tenant isolation' }
    let(:french_description) { 'Autorisation en francais' }
    let(:raw_description) { N_('RiskAssessment|Authorization, access control, or tenant isolation') }

    let(:domain) do
      described_class.new(
        name: 'authorization',
        severity: 'high',
        description: raw_description
      )
    end

    let(:fr_translations) do
      { raw_description => french_description }
    end

    context 'when the locale has no translation' do
      it 'strips the namespace when the locale has no translation' do
        expect(description).to eq(english_description)
      end
    end

    context 'when locale is not English' do
      it 'returns the translated description' do
        with_stubbed_translations(:fr, fr_translations) do
          expect(description).to eq(french_description)
        end
      end
    end
  end
end
