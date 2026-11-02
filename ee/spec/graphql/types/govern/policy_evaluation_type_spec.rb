# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GovernPolicyEvaluation'], feature_category: :security_policy_management do
  include GraphqlHelpers

  specify do
    expect(described_class).to have_graphql_fields(
      :id, :policy_id, :trigger_type, :mode, :verdict, :policy_version, :evaluated_at,
      :project_id, :project, :environment_id, :user_id, :violations
    )
  end

  describe '#project' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:policy) { create(:govern_policy, :without_namespace, organization: organization) }
    let_it_be(:project) { create(:project, organization: organization) }

    let(:evaluation) do
      build_stubbed(:govern_policy_evaluation, policy: policy, organization: organization,
        project_id: project_id)
    end

    subject(:resolved) { batch_sync { resolve_field(:project, evaluation) } }

    context 'when the evaluation names a project' do
      let(:project_id) { project.id }

      it { is_expected.to eq(project) }
    end

    # project_id carries no foreign key, so a stale or mis-written id could otherwise
    # name a project in another organization and render it as this policy's project.
    context 'when the named project belongs to another organization' do
      let_it_be(:foreign_project) { create(:project) }

      let(:project_id) { foreign_project.id }

      it { is_expected.to be_nil }
    end

    # project_id carries no foreign key, so a deleted project leaves the id behind.
    context 'when the project no longer exists' do
      let(:project_id) { non_existing_record_id }

      it { is_expected.to be_nil }
    end

    context 'when the evaluation is not scoped to a project' do
      let(:project_id) { nil }

      it { is_expected.to be_nil }
    end
  end
end
