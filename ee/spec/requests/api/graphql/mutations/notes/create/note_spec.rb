# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Adding a Note to an Epic', feature_category: :portfolio_management do
  include GraphqlHelpers
  include WorkItemTypeVisibilityHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group, :private) }
  # `freeze: false` is required in this spec: one or more `let_it_be` subjects
  # cannot be frozen by default (deep_freeze traversal failure, a non-AR
  # subject, or an in-memory mutation that survives reload/refind). Do not
  # drop these opt-outs or convert them to `let_it_be_with_reload`/`refind`
  # (see gitlab-org/gitlab#602925).
  let_it_be(:noteable, freeze: false) { create(:epic, group: group) }

  let(:body) { 'Body text' }
  let(:variables_extra) { {} }
  let(:variables) do
    {
      noteable_id: GitlabSchema.id_from_object(noteable).to_s,
      body: body
    }.merge(variables_extra)
  end

  let(:mutation) do
    graphql_mutation(:create_note, variables)
  end

  def mutation_response
    graphql_mutation_response(:create_note)
  end

  before do
    stub_licensed_features(epics: true)
  end

  context 'when the user does not have permission' do
    it_behaves_like 'a Note mutation when the user does not have permission'
  end

  context 'when the user has permission' do
    before_all do
      group.add_developer(current_user)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :create_note do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:request) do
        post_graphql_mutation(
          graphql_mutation(:create_note, { noteable_id: global_id_of(noteable).to_s, body: 'a note' }, 'errors'),
          token: { personal_access_token: pat })
      end
    end

    context 'when using internal param' do
      let(:variables_extra) { { internal: true } }

      it_behaves_like 'a Note mutation with confidential notes'
    end

    context 'when body contains quick actions' do
      let_it_be(:project) { create(:project, group: group) }
      # `freeze: false` is required in this spec: one or more `let_it_be` subjects
      # cannot be frozen by default (deep_freeze traversal failure, a non-AR
      # subject, or an in-memory mutation that survives reload/refind). Do not
      # drop these opt-outs or convert them to `let_it_be_with_reload`/`refind`
      # (see gitlab-org/gitlab#602925).
      let_it_be(:noteable, freeze: false) { create(:work_item, :issue, project: project) }

      let(:variables_extra) { {} }

      before do
        stub_licensed_features(issuable_health_status: true, issue_weights: true, epics: true)
      end

      it_behaves_like 'work item supports weights widget updates via quick actions'
      it_behaves_like 'work item does not support weights widget updates via quick actions'
      it_behaves_like 'work item supports health status widget updates via quick actions'
      it_behaves_like 'work item does not support health status widget updates via quick actions'
      it_behaves_like 'work item supports promotion via quick actions'
    end

    context 'with legacy /promote when promotion fails' do
      let_it_be(:project) { create(:project, group: group) }
      let_it_be_with_reload(:noteable) { create(:issue, project: project) }

      let(:body) { '/promote' }

      before do
        allow_next_instance_of(Issues::UpdateService) do |service|
          allow(service).to receive(:handle_promotion) do
            service.send(:params).delete(:promote_to_epic)
            'Promotion failed.'
          end
        end
      end

      it 'returns the error without the promote success message', :aggregate_failures do
        post_graphql_mutation(mutation, current_user: current_user)

        status = mutation_response['quickActionsStatus']
        expect(status['errorMessages']).to eq(['Promotion failed.'])
        expect(status['messages']).to be_nil
      end

      context 'with another command' do
        let(:body) { "/promote\n/close" }

        it 'keeps the message of the other command', :aggregate_failures do
          post_graphql_mutation(mutation, current_user: current_user)

          status = mutation_response['quickActionsStatus']
          expect(status['errorMessages']).to eq(['Promotion failed.'])
          expect(status['messages']).to eq(['Closed this issue.'])
          expect(noteable.reload).to be_closed
        end
      end
    end

    context 'with work item epic' do
      # `freeze: false` is required in this spec: one or more `let_it_be` subjects
      # cannot be frozen by default (deep_freeze traversal failure, a non-AR
      # subject, or an in-memory mutation that survives reload/refind). Do not
      # drop these opt-outs or convert them to `let_it_be_with_reload`/`refind`
      # (see gitlab-org/gitlab#602925).
      let_it_be(:noteable, freeze: false) { create(:work_item, :epic, namespace: group) }

      it_behaves_like 'a Note mutation that creates a Note'

      context 'without group level work item license' do
        before do
          stub_licensed_features(epics: false)
        end

        it_behaves_like 'a Note mutation when the user does not have permission'
      end

      context 'when work item has synced epic' do
        let_it_be(:synced_epic) { create(:epic, :with_synced_work_item, group: group) }
        let_it_be(:noteable) { synced_epic.work_item }

        it_behaves_like 'a Note mutation that creates a Note'
      end
    end
  end

  context 'when promoting to a disabled epic type' do
    let_it_be(:availability_group) { create(:group) }
    let_it_be(:availability_project) { create(:project, group: availability_group) }
    let_it_be(:developer) { create(:user, developer_of: availability_group) }
    let_it_be(:noteable) { create(:work_item, :issue, project: availability_project) }

    before do
      stub_saas_features(namespace_scoped_work_item_types: true)
      stub_licensed_features(epics: true, configurable_work_item_types: true)
      disable_work_item_types(availability_group, :epic)
    end

    it 'does not promote the issue' do
      expect do
        post_graphql_mutation(
          graphql_mutation(:create_note, { noteable_id: noteable.to_global_id.to_s, body: '/promote_to epic' }),
          current_user: developer)
      end.not_to change { WorkItem.count }

      expect(mutation_response['quickActionsStatus']['messages'])
        .to include(a_string_including('Work item type Epic is disabled or archived for this project or group.'))
      expect(noteable.reload).to be_opened
    end
  end
end
