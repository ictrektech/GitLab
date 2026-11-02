# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::JobArtifactPolicy, feature_category: :job_artifacts do
  let(:user) { build(:user) }
  let(:job_artifact) { build(:ci_job_artifact) }

  subject { described_class.new(user, job_artifact) }

  it { is_expected.to delegate_to(Authz::JobArtifactAccessPolicy) }

  # Some callers authorize Authz::JobArtifactAccess directly, so a rule here would not
  # apply to them. Add new conditions to Authz::JobArtifactAccessPolicy, and any new
  # attribute they read to Authz::JobArtifactAccess.
  it 'only delegates to the access subject' do
    expect(described_class.own_conditions).to be_empty
    expect(described_class.own_ability_map.map).to be_empty
    expect(described_class.own_global_actions).to be_empty
    expect(described_class.own_delegations.size).to eq(1)
  end

  describe '.preload_for_batch_checks' do
    let_it_be(:artifacts) do
      create_list(:project, 2).map do |project|
        create(:ci_job_artifact, :junit, job: create(:ci_build, project: project))
      end
    end

    it 'loads the jobs and projects the delegated subject reads' do
      records = Ci::JobArtifact.id_in(artifacts).to_a

      described_class.preload_for_batch_checks(records, user)

      expect { records.each { |artifact| artifact.job.project } }.not_to exceed_query_limit(0)
    end
  end
end
