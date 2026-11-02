# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::WorkItems::Create, feature_category: :portfolio_management do
  include WorkItemTypeVisibilityHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private, reporters: user) }
  let_it_be(:project) { create(:project, :private, group: group, reporters: user) }

  let_it_be(:epic_type) { build(:work_item_system_defined_type, :epic) }

  before do
    stub_feature_flags(work_item_rest_api: user)
  end

  describe 'POST /projects/:id/-/work_items' do
    let(:api_request_path) { "/projects/#{project.id}/-/work_items" }

    context 'with health_status feature' do
      before do
        stub_licensed_features(issuable_health_status: true)
      end

      it 'creates a work item with health status' do
        post api(api_request_path, user), params: {
          title: 'Healthy issue',
          work_item_type_name: 'issue',
          features: { health_status: { health_status: 'on_track' } }
        }

        expect(response).to have_gitlab_http_status(:created)
        expect(WorkItem.find(json_response['id']).health_status).to eq('on_track')
      end
    end

    context 'with iteration feature' do
      let_it_be(:iteration_cadence) { create(:iterations_cadence, group: group) }
      let_it_be(:iteration) { create(:iteration, iterations_cadence: iteration_cadence) }

      before do
        stub_licensed_features(iterations: true)
      end

      it 'creates a work item with an iteration' do
        post api(api_request_path, user), params: {
          title: 'Iterated issue',
          work_item_type_name: 'issue',
          features: { iteration: { iteration_id: iteration.id } }
        }

        expect(response).to have_gitlab_http_status(:created)
        expect(WorkItem.find(json_response['id']).iteration).to eq(iteration)
      end

      it 'returns not found for an iteration outside the work item group hierarchy' do
        other_group = create(:group, :private)
        other_cadence = create(:iterations_cadence, group: other_group)
        other_iteration = create(:iteration, iterations_cadence: other_cadence)

        post api(api_request_path, user), params: {
          title: 'Cross-group iteration issue',
          work_item_type_name: 'issue',
          features: { iteration: { iteration_id: other_iteration.id } }
        }

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'creates a work item with null iteration (unset)' do
        post api(api_request_path, user), params: {
          title: 'Unset iteration issue',
          work_item_type_name: 'issue',
          features: { iteration: { iteration_id: nil } }
        }

        expect(response).to have_gitlab_http_status(:created)
        expect(WorkItem.find(json_response['id']).iteration).to be_nil
      end

      it 'returns not found for a non-existent iteration ID' do
        post api(api_request_path, user), params: {
          title: 'Bad iteration issue',
          work_item_type_name: 'issue',
          features: { iteration: { iteration_id: non_existing_record_id } }
        }

        expect(response).to have_gitlab_http_status(:not_found)
      end

      context 'when the iterations license is disabled' do
        before do
          stub_licensed_features(iterations: false)
        end

        it 'silently ignores the iteration widget and succeeds' do
          post api(api_request_path, user), params: {
            title: 'Iteration ignored issue',
            work_item_type_name: 'issue',
            features: { iteration: { iteration_id: iteration.id } }
          }

          expect(response).to have_gitlab_http_status(:created)
          expect(WorkItem.find(json_response['id']).iteration).to be_nil
        end
      end
    end

    context 'with weight feature' do
      before do
        stub_licensed_features(issue_weights: true)
      end

      it 'creates a work item with weight' do
        post api(api_request_path, user), params: {
          title: 'Weighted task',
          work_item_type_name: 'task',
          features: { weight: { weight: 5 } }
        }

        expect(response).to have_gitlab_http_status(:created)
        expect(WorkItem.find(json_response['id']).weight).to eq(5)
      end

      it 'creates a work item with null weight' do
        post api(api_request_path, user), params: {
          title: 'Unweighted task',
          work_item_type_name: 'task',
          features: { weight: { weight: nil } }
        }

        expect(response).to have_gitlab_http_status(:created)
        expect(WorkItem.find(json_response['id']).weight).to be_nil
      end
    end

    context 'with status feature' do
      before do
        stub_licensed_features(work_item_status: true)
      end

      it 'creates a work item with a system-defined status' do
        status = WorkItems::Statuses::SystemDefined::Status.all.first

        post api(api_request_path, user), params: {
          title: 'Status task',
          work_item_type_name: 'task',
          features: { status: { status_id: status.id } }
        }

        expect(response).to have_gitlab_http_status(:created)
      end

      it 'creates a work item with a custom status' do
        lifecycle = create(:work_item_custom_lifecycle, :for_tasks, namespace: group)
        custom_status = lifecycle.default_open_status

        post api(api_request_path, user), params: {
          title: 'Status task',
          work_item_type_name: 'task',
          features: { status: { status_id: custom_status.id } }
        }

        expect(response).to have_gitlab_http_status(:created)
      end

      it 'returns not found for a non-existent system-defined status ID' do
        # No custom lifecycle exists for this group, so system-defined lookup is used
        post api(api_request_path, user), params: {
          title: 'Status task',
          work_item_type_name: 'task',
          features: { status: { status_id: non_existing_record_id } }
        }

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'returns not found for a non-existent custom status ID' do
        create(:work_item_custom_lifecycle, :for_tasks, namespace: group)

        post api(api_request_path, user), params: {
          title: 'Status task',
          work_item_type_name: 'task',
          features: { status: { status_id: non_existing_record_id } }
        }

        expect(response).to have_gitlab_http_status(:not_found)
      end

      it 'creates a work item when status_id is null' do
        post api(api_request_path, user), params: {
          title: 'No status task',
          work_item_type_name: 'task',
          features: { status: { status_id: nil } }
        }

        expect(response).to have_gitlab_http_status(:created)
      end
    end

    context 'with custom_fields feature' do
      before do
        stub_licensed_features(custom_fields: true)
      end

      it 'creates a work item with a custom field value' do
        task_type = build(:work_item_system_defined_type, :task)
        custom_field = create(:custom_field, :number, namespace: group)
        create(:work_item_type_custom_field, custom_field: custom_field, work_item_type: task_type)

        post api(api_request_path, user), params: {
          title: 'Custom field task',
          work_item_type_name: 'task',
          features: {
            custom_fields: [
              { custom_field_id: custom_field.id, number_value: 42 }
            ]
          }
        }

        expect(response).to have_gitlab_http_status(:created)
        work_item = WorkItem.find(json_response['id'])
        value = WorkItems::NumberFieldValue.for_field_and_work_item(custom_field.id, work_item.id).first
        expect(value&.value.to_i).to eq(42)
      end
    end

    context 'when authenticated with a token that has the ai_workflows scope' do
      let_it_be(:ai_label) { create(:label, project: project) }

      let(:oauth_token) do
        create(:oauth_access_token, user: user, scopes: [:api, :ai_workflows])
      end

      it 'forbids a blocked quick action and creates nothing' do
        expect do
          post api(api_request_path, oauth_access_token: oauth_token), params: {
            title: 'Blocked task',
            work_item_type_name: 'issue',
            features: { description: { description: '/close' } }
          }
        end.not_to change { WorkItem.count }

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['message']).to include('Quick actions close cannot be used with AI workflows')
      end

      it 'allows a permitted quick action' do
        post api(api_request_path, oauth_access_token: oauth_token), params: {
          title: 'Labeled task',
          work_item_type_name: 'issue',
          features: { description: { description: "/label ~#{ai_label.name}" } }
        }

        expect(response).to have_gitlab_http_status(:created)
        expect(WorkItem.find(json_response['id']).labels).to include(ai_label)
      end
    end

    context 'when work item types are disabled at the project level' do
      let_it_be(:availability_group) { create(:group, :private, reporters: user) }
      let_it_be(:availability_project) { create(:project, :private, group: availability_group) }
      let_it_be_with_reload(:custom_type) { create(:work_item_custom_type, namespace: availability_group) }

      let(:project_work_items_path) { "/projects/#{availability_project.id}/-/work_items" }

      before do
        stub_licensed_features(quality_management: true, configurable_work_item_types: true)
        disable_work_item_types(availability_project.project_namespace, :issue, :incident, :test_case)
      end

      context 'with disabled system-defined types' do
        where(:work_item_type_name, :flag_enabled) { %w[issue incident test_case].product([true, false]) }

        with_them do
          before do
            stub_feature_flags(enforce_work_item_type_availability: flag_enabled)
          end

          it 'does not create the work item' do
            expect do
              post api(project_work_items_path, user), params: {
                title: 'new item',
                work_item_type_name: work_item_type_name
              }
            end.not_to change { WorkItem.count }

            expect(response).to have_gitlab_http_status(:unprocessable_entity)
            expect(json_response['message'])
              .to eq("Work item type #{work_item_type_name.titleize} is disabled or archived for this project " \
                'or group.')
          end
        end
      end

      context 'with an unavailable custom type' do
        where(:custom_type_state) { %i[disabled archived] }

        with_them do
          before do
            if custom_type_state == :archived
              custom_type.update!(archived: true)
            else
              disable_work_item_types(availability_project.project_namespace, custom_type)
            end
          end

          it 'does not create the work item with the custom type' do
            expect do
              post api(project_work_items_path, user), params: { title: 'new item', work_item_type_id: custom_type.id }
            end.not_to change { WorkItem.count }

            expect(response).to have_gitlab_http_status(:unprocessable_entity)
            expect(json_response['message'])
              .to eq("Work item type #{custom_type.name} is disabled or archived for this project or group.")
          end

          context 'when enforce_work_item_type_availability is disabled' do
            before do
              stub_feature_flags(enforce_work_item_type_availability: false)
            end

            it 'creates the work item with the custom type as before' do
              post api(project_work_items_path, user), params: { title: 'new item', work_item_type_id: custom_type.id }

              expect(response).to have_gitlab_http_status(:created)
              expect(WorkItem.find(json_response['id']).work_item_type).to eq(custom_type)
            end
          end
        end
      end
    end
  end

  describe 'POST /namespaces/:id/-/work_items' do
    context 'when namespace is a group namespace and epics are supported' do
      before do
        stub_licensed_features(epics: true)
      end

      it 'creates a group-level work item via the namespace endpoint' do
        post api("/namespaces/#{CGI.escape(group.full_path)}/-/work_items", user), params: {
          title: 'Group epic via namespace',
          work_item_type_id: epic_type.id
        }

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['title']).to eq('Group epic via namespace')
      end

      it_behaves_like 'authorizing granular token permissions', :create_work_item do
        let(:boundary_object) { group }
        let(:request) do
          post api("/namespaces/#{CGI.escape(group.full_path)}/-/work_items", personal_access_token: pat),
            params: { title: 'Group epic via namespace', work_item_type_id: epic_type.id }
        end
      end
    end
  end

  describe 'POST /groups/:id/-/work_items' do
    let(:api_request_path) { "/groups/#{group.id}/-/work_items" }

    context 'when group work items are supported (epic type)' do
      before do
        stub_licensed_features(epics: true)
      end

      it 'creates a group-level work item' do
        post api(api_request_path, user), params: {
          title: 'Group epic',
          work_item_type_id: epic_type.id
        }

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['title']).to eq('Group epic')
      end

      it_behaves_like 'authorizing granular token permissions', :create_work_item do
        let(:boundary_object) { group }
        let(:request) do
          post api("/groups/#{group.id}/-/work_items", personal_access_token: pat),
            params: { title: 'Group epic', work_item_type_id: epic_type.id }
        end
      end
    end

    context 'when the epic type is disabled' do
      let_it_be(:epic_type) { build(:work_item_system_defined_type, :epic) }

      where(:flag_enabled) { [true, false] }

      with_them do
        before do
          stub_licensed_features(epics: true)
          stub_feature_flags(enforce_work_item_type_availability: flag_enabled)
          disable_work_item_types(group, epic_type)
        end

        it 'does not create the epic' do
          expect do
            post api(api_request_path, user), params: { title: 'Group epic', work_item_type_id: epic_type.id }
          end.not_to change { WorkItem.count }

          expect(response).to have_gitlab_http_status(:unprocessable_entity)
          expect(json_response['message'])
            .to eq('Work item type Epic is disabled or archived for this project or group.')
        end
      end
    end
  end
end
