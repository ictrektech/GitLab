# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::JiraImport, feature_category: :importers do
  include JiraIntegrationHelpers

  describe '.validate_project_settings!' do
    let_it_be_with_reload(:project) { create(:project) }
    let_it_be(:user) { create(:user, maintainer_of: project) }

    let!(:jira_integration) { create(:jira_integration, project: project, active: true) }

    subject(:validate) { described_class.validate_project_settings!(project, user: user) }

    before do
      stub_jira_integration_test
    end

    context 'when continuous GitHub sync is on' do
      before do
        project.update!(import_type: 'github')
        create(:import_sync_repository, project: project, authority_state: :provider_canonical)
        project.association(:import_sync_repository).reset
      end

      it 'raises, after the CE checks have already passed' do
        expect { validate }.to raise_error(
          Projects::ImportService::Error, 'Cannot import because updates from GitHub are on for this project.'
        )
      end

      it 'still rejects an unauthorized user with the CE permissions error, not the GitHub-sync error' do
        unauthorized_user = create(:user, developer_of: project)

        expect { described_class.validate_project_settings!(project, user: unauthorized_user) }.to raise_error(
          Projects::ImportService::Error, 'You do not have permissions to run the import.'
        )
      end
    end

    context 'when continuous GitHub sync is off' do
      before do
        project.update!(import_type: 'github')
        create(:import_sync_repository, project: project, authority_state: :gitlab_canonical)
        project.association(:import_sync_repository).reset
      end

      it 'does not raise' do
        expect { validate }.not_to raise_error
      end
    end
  end
end
