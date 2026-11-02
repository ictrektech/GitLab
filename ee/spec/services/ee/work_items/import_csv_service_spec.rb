# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::ImportCsvService, feature_category: :team_planning do
  include WorkItemTypeVisibilityHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:author) { create(:user, username: 'csv_author') }
  let_it_be(:project) { create(:project, maintainers: user) }
  let(:file) { fixture_file_upload('ee/spec/fixtures/work_items_valid_types.csv') }
  let(:service) do
    uploader = FileUploader.new(project)
    uploader.store!(file)

    described_class.new(user, project, uploader)
  end

  let_it_be(:issue_type) { build(:work_item_system_defined_type, :issue) }
  let_it_be(:requirement_type) { build(:work_item_system_defined_type, :requirement) }

  let(:work_items) { ::WorkItems::WorkItemsFinder.new(user, project: project).execute }

  subject { service.execute }

  describe '#execute', :aggregate_failures do
    before do
      stub_licensed_features(requirements: true)
    end

    context 'when file is valid' do
      context 'when all types are available' do
        it 'creates the expected number of work items' do
          expect { subject }.to change { work_items.count }.by 2
        end

        it 'sets work item attributes' do
          result = subject

          expect(work_items.reload).to contain_exactly(
            have_attributes(
              title: 'Valid issue',
              work_item_type_id: issue_type.id
            ),
            have_attributes(
              title: 'Valid requirement',
              work_item_type_id: requirement_type.id
            )
          )

          expect(result[:success]).to eq(2)
          expect(result[:error_lines]).to be_empty
          expect(result[:type_errors]).to be_nil
          expect(result[:parse_error]).to be(false)
        end
      end

      context 'when some types are unavailable' do
        let(:file) { fixture_file_upload('ee/spec/fixtures/work_items_invalid_types.csv') }

        it 'throws an error and does not import' do
          result = subject

          expect(result[:parse_error]).to be(false)
          expect(result[:type_errors]).to match({
            blank: [],
            disallowed: { "epic" => [5] }, # tested in the EE version
            missing: {
              "issue!!!" => [2],
              "requirement🔨" => [3],
              "nonsense??" => [4]
            },
            unavailable: {}
          })
        end
      end

      context 'when the csv contains epic type' do
        let(:file) { fixture_file_upload('ee/spec/fixtures/work_items_epic_type.csv') }

        it 'does not import' do
          expect { subject }.not_to change { work_items.count }
        end

        it 'classifies epic as disallowed' do
          result = subject

          expect(result[:parse_error]).to be(false)
          expect(result[:type_errors]).to match({
            blank: [],
            disallowed: { "epic" => [2] },
            missing: {},
            unavailable: {}
          })
        end

        context 'when project-level epics are enabled' do
          before do
            stub_licensed_features(requirements: true, epics: true)
            stub_feature_flags(project_work_item_epics: true)
          end

          it 'still classifies epic as disallowed' do
            expect(subject[:type_errors]).to match({
              blank: [], disallowed: { "epic" => [2] }, missing: {}, unavailable: {}
            })
          end
        end
      end

      context 'when csv contains work item types with spaces in their name' do
        let(:file) { fixture_file_upload('ee/spec/fixtures/work_items_key_result.csv') }

        before do
          stub_feature_flags(okrs_mvc: true)
          stub_licensed_features(okrs: true)
        end

        it 'returns the correct result' do
          result = subject

          expect(result[:success]).to eq(1)
          expect(result[:error_lines]).to be_empty
          expect(result[:parse_error]).to be(false)
          expect(result[:type_errors]).to be_nil
        end
      end
    end

    context 'when user cannot create type' do
      context 'when types include Requirement' do
        shared_examples 'does not create requirement' do
          specify do
            result = subject

            expect(work_items.reload).not_to include(
              have_attributes(
                title: 'Valid requirement'
              )
            )

            expect(result[:parse_error]).to be(false)
            expect(result[:type_errors]).to match({
              blank: [],
              disallowed: { "requirement" => [3] },
              missing: {},
              unavailable: {}
            })
          end
        end

        context 'when Requirement is not licensed' do
          before do
            stub_licensed_features(requirements: false)
          end

          it_behaves_like 'does not create requirement'
        end

        context 'when user cannot create a Requirement' do
          before do
            allow(Ability).to receive(:allowed?).and_call_original
            allow(Ability).to receive(:allowed?).with(user, :create_requirement, anything).and_return(false)
          end

          it_behaves_like 'does not create requirement'
        end
      end
    end

    context 'when csv contains custom work item types' do
      let_it_be(:group) { create(:group) }
      let_it_be(:project_in_group) { create(:project, group: group, maintainers: user) }
      let_it_be(:custom_type) { create(:work_item_custom_type, name: 'Story', namespace: group) }

      let(:file) { fixture_file_upload('ee/spec/fixtures/work_items_custom_types.csv') }
      let(:service) do
        uploader = FileUploader.new(project_in_group)
        uploader.store!(file)

        described_class.new(user, project_in_group, uploader)
      end

      let(:work_items) { ::WorkItems::WorkItemsFinder.new(user, project: project_in_group).execute }

      before do
        stub_licensed_features(configurable_work_item_types: true)
        stub_saas_features(namespace_scoped_work_item_types: true)
      end

      it 'creates work items with the custom type, matching case-insensitively and stripping whitespace' do
        expect { subject }.to change { work_items.count }.by(1)
      end

      it 'sets the correct custom work item type' do
        result = subject

        expect(work_items.reload).to contain_exactly(
          have_attributes(title: 'Story work item')
        )
        expect(work_items.first.work_item_type).to eq(custom_type)

        expect(result[:success]).to eq(1)
        expect(result[:error_lines]).to be_empty
        expect(result[:type_errors]).to be_nil
        expect(result[:parse_error]).to be(false)
      end

      context 'when the custom type is disabled for the namespace via Visibility' do
        before do
          disable_work_item_types(group, custom_type)
        end

        it 'does not import' do
          expect { subject }.not_to change { work_items.count }
        end

        it 'returns the type as unavailable' do
          result = subject

          expect(result[:parse_error]).to be(false)
          expect(result[:type_errors]).to match({
            blank: [],
            disallowed: {},
            missing: {},
            unavailable: { "Story" => [2] }
          })
        end
      end
    end

    context 'when the issue type is disabled at the project level' do
      let_it_be(:group) { create(:group) }
      let_it_be(:project_in_group) { create(:project, group: group, maintainers: user) }

      let(:service) do
        uploader = FileUploader.new(project_in_group)
        uploader.store!(file)

        described_class.new(user, project_in_group, uploader)
      end

      before do
        disable_work_item_types(project_in_group.project_namespace, issue_type)
      end

      it 'reports the explicit issue rows as unavailable and creates nothing' do
        result = nil

        expect { result = subject }.not_to change { WorkItem.count }

        expect(result[:success]).to eq(0)
        expect(result[:type_errors]).to match({
          blank: [],
          disallowed: {},
          missing: {},
          unavailable: { "Issue" => [2] }
        })
      end

      context 'when the type column is missing' do
        let(:file) { fixture_file_upload('spec/fixtures/work_items_no_type.csv') }

        it 'reports the fallback issue rows as unavailable and creates nothing' do
          result = nil

          expect { result = subject }.not_to change { WorkItem.count }

          expect(result[:type_errors]).to match({
            blank: [],
            disallowed: {},
            missing: {},
            unavailable: { "Issue" => [2, 3] }
          })
        end
      end

      context 'when the csv contains epic type and epic is disabled' do
        let(:file) { fixture_file_upload('ee/spec/fixtures/work_items_epic_type.csv') }

        before do
          stub_licensed_features(requirements: true, epics: true)
          stub_feature_flags(project_work_item_epics: true)
          disable_work_item_types(project_in_group.project_namespace, :epic)
        end

        it 'reports epic as disallowed, not unavailable' do
          expect(subject[:type_errors]).to match({
            blank: [], disallowed: { "epic" => [2] }, missing: {}, unavailable: {}
          })
        end
      end
    end
  end
end
