# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Elastic::RecordProxy::SbomOccurrenceRef, feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:occurrence_ref) { create(:sbom_occurrence_ref, project: project) }

  let(:enhancements) { { policy_violations: ::Security::PolicyViolations::DISMISSED_IN_MR, malware: true } }

  describe 'inheritance' do
    it 'inherits from Search::Elastic::RecordProxy::Base' do
      expect(described_class.superclass).to eq(Search::Elastic::RecordProxy::Base)
    end
  end

  describe '.create_with_enhancements' do
    subject(:proxy) { described_class.create_with_enhancements(occurrence_ref, enhancements) }

    it 'answers for the enhanced fields' do
      expect(proxy.policy_violations).to eq(::Security::PolicyViolations::DISMISSED_IN_MR)
      expect(proxy.malware).to be(true)
    end

    it 'delegates everything else to the underlying record' do
      expect(proxy.id).to eq(occurrence_ref.id)
      expect(proxy.project_id).to eq(project.id)
      expect(proxy.occurrence).to eq(occurrence_ref.occurrence)
    end

    it 'leaves the underlying record unenhanced' do
      proxy

      expect(occurrence_ref).not_to respond_to(:policy_violations)
    end
  end
end
