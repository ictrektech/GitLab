# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Autocomplete::UsersFinder, feature_category: :code_review_workflow do
  include Ai::Catalog::FlowFactoryHelpers

  describe '#execute' do
    let(:current_user) { create(:user) }
    let(:params) { {} }

    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }

    subject(:users) do
      described_class.new(params: params, current_user: current_user, project: project, group: nil).execute.to_a
    end

    describe '#project_users' do
      let_it_be(:duo_code_review_bot) { ::Users::Internal.in_organization(project.organization_id).duo_code_review_bot }

      context 'when project does not have access to Duo Code review' do
        before do
          allow(project).to receive(:ai_review_merge_request_allowed?).with(current_user).and_return(false)
        end

        it { is_expected.not_to include(duo_code_review_bot) }
      end

      context 'when project has access Duo Code review' do
        before do
          allow(project).to receive(:ai_review_merge_request_allowed?).with(current_user).and_return(true)
        end

        it { is_expected.to include(duo_code_review_bot) }
      end
    end
  end
end
