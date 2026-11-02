# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackWorkspace::Workspace, feature_category: :integrations do
  subject(:workspace) { build(:slack_workspace) }

  describe 'associations' do
    it { is_expected.to belong_to(:duo_namespace).class_name('Namespace').required }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:team_id) }
    it { is_expected.to validate_length_of(:team_id).is_at_most(255) }

    it 'allows one row per Slack workspace' do
      create(:slack_workspace, team_id: 'T_ACME')

      expect(build(:slack_workspace, team_id: 'T_ACME')).not_to be_valid
    end

    it 'needs a top-level group' do
      expect(build(:slack_workspace, duo_namespace: create(:group, parent: create(:group)))).not_to be_valid
      expect(build(:slack_workspace, duo_namespace: create(:user).namespace)).not_to be_valid
    end
  end

  it 'is deleted with its group' do
    workspace = create(:slack_workspace)

    workspace.duo_namespace.destroy!

    expect(described_class.exists?(workspace.id)).to be(false)
  end
end
