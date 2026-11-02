# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::GithubImport::Settings, feature_category: :importers do
  describe '.stages_array' do
    let_it_be(:user) { create(:user) }

    let(:oauth) { true }
    let(:stage_names) { described_class.stages_array(user, oauth: oauth).pluck(:name) }

    context 'when namespace plans are checked', :saas do
      before do
        stub_licensed_features(github_continuous_sync: false)
      end

      it 'includes the continuous sync stage regardless of the instance license' do
        expect(stage_names).to include('continuous_sync')
      end
    end

    context 'when namespace plans are not checked' do
      context 'when the instance is licensed' do
        before do
          stub_licensed_features(github_continuous_sync: true)
        end

        it 'includes the unselected continuous sync stage' do
          expect(described_class.stages_array(user, oauth: true)).to include(
            name: 'continuous_sync',
            label: s_('GitHubImporter|Keep this project updated from GitHub'),
            selected: false,
            details: s_('GitHubImporter|Keep the imported project up to date with changes from ' \
              'GitHub. Requires GitLab Premium or Ultimate.')
          )
        end
      end

      context 'when the instance is not licensed' do
        before do
          stub_licensed_features(github_continuous_sync: false)
        end

        it 'excludes the continuous sync stage and keeps the other stages' do
          expect(stage_names).to contain_exactly('attachments_import', 'collaborators_import')
        end
      end
    end

    context 'when the github_continuous_import feature flag is disabled', :saas do
      before do
        stub_feature_flags(github_continuous_import: false)
        stub_licensed_features(github_continuous_sync: true)
      end

      it 'excludes the continuous sync stage' do
        expect(stage_names).to contain_exactly('attachments_import', 'collaborators_import')
      end
    end

    context 'when authenticated with a personal access token', :saas do
      let(:oauth) { false }

      before do
        stub_licensed_features(github_continuous_sync: true)
      end

      it 'excludes the continuous sync stage' do
        expect(stage_names).to contain_exactly('attachments_import', 'collaborators_import')
      end
    end
  end
end
