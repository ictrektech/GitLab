# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProjectSetting, feature_category: :groups_and_projects do
  it { is_expected.to belong_to(:push_rule) }
  it { is_expected.to validate_length_of(:product_analytics_instrumentation_key).is_at_most(255).allow_blank }

  it { is_expected.to allow_value('https://test.com').for(:product_analytics_configurator_connection_string) }
  it { is_expected.to allow_value('https://test.com').for(:product_analytics_data_collector_host) }
  it { is_expected.to allow_value('https://test.com').for(:cube_api_base_url) }

  it { is_expected.to allow_value('').for(:product_analytics_configurator_connection_string) }
  it { is_expected.to allow_value('').for(:product_analytics_data_collector_host) }
  it { is_expected.to allow_value('').for(:cube_api_base_url) }
  it { is_expected.to allow_value('').for(:cube_api_key) }

  it { is_expected.not_to allow_value('notavalidurl').for(:product_analytics_configurator_connection_string) }
  it { is_expected.not_to allow_value('notavalidurl').for(:product_analytics_data_collector_host) }
  it { is_expected.not_to allow_value('notavalidurl').for(:cube_api_base_url) }

  it { is_expected.to validate_length_of(:product_analytics_configurator_connection_string).is_at_most(512) }
  it { is_expected.to validate_length_of(:product_analytics_data_collector_host).is_at_most(255) }
  it { is_expected.to validate_length_of(:cube_api_base_url).is_at_most(512) }
  it { is_expected.to validate_length_of(:cube_api_key).is_at_most(255) }

  describe 'duo_context_exclusion_settings validation' do
    it { is_expected.to allow_value({}).for(:duo_context_exclusion_settings) }
    it { is_expected.to allow_value({ exclusion_rules: [] }).for(:duo_context_exclusion_settings) }
    it { is_expected.to allow_value({ exclusion_rules: ['test.log', '.tmp'] }).for(:duo_context_exclusion_settings) }

    it { is_expected.not_to allow_value(nil).for(:duo_context_exclusion_settings) }
    it { is_expected.not_to allow_value('invalid_string').for(:duo_context_exclusion_settings) }
    it { is_expected.not_to allow_value([]).for(:duo_context_exclusion_settings) }
    it { is_expected.not_to allow_value({ exclusion_rules: 'not_an_array' }).for(:duo_context_exclusion_settings) }
    it { is_expected.not_to allow_value({ exclusion_rules: [123, 456] }).for(:duo_context_exclusion_settings) }
    it { is_expected.not_to allow_value({ invalid_property: ['.log'] }).for(:duo_context_exclusion_settings) }

    it 'now allow extra properties' do
      is_expected.not_to allow_value({ exclusion_rules: ['.log'],
     extra_property: 'no' }).for(:duo_context_exclusion_settings)
    end

    context 'with the size limit' do
      let(:at_limit) { { exclusion_rules: ['a' * (64.kilobytes - 24)] } }
      let(:over_limit) { { exclusion_rules: ['a' * (64.kilobytes - 23)] } }

      it { is_expected.to allow_value(at_limit).for(:duo_context_exclusion_settings) }

      it 'rejects rules larger than 64 KiB' do
        is_expected.not_to allow_value(over_limit)
          .for(:duo_context_exclusion_settings)
          .with_message('is too large. Maximum size allowed is 64 KiB')
      end

      it 'does not block saving other settings when the stored rules are already over the limit' do
        setting = create(:project_setting)
        setting.update_column(:duo_context_exclusion_settings, over_limit)

        expect(setting.reload.update(show_default_award_emojis: false)).to be(true)
      end
    end
  end

  describe '.has_vulnerabilities' do
    let_it_be(:setting_1) { create(:project_setting, :has_vulnerabilities) }
    let_it_be(:setting_2) { create(:project_setting) }

    subject { described_class.has_vulnerabilities }

    it { is_expected.to contain_exactly(setting_1) }
  end

  describe '.has_confluence?' do
    let_it_be(:setting, freeze: false) { create(:project_setting, has_confluence: true) }

    subject { setting }

    it { is_expected.to have_confluence }

    it 'is false when the confluence integration is blocked by settings' do
      allow(Integrations::Confluence).to receive(:blocked_by_settings?).and_return(true)

      is_expected.not_to have_confluence
    end
  end

  describe 'all_or_none_product_analytics_attributes_set' do
    let_it_be(:setting, freeze: false) { create(:project_setting) }

    subject { setting }

    context 'when setting all values' do
      before do
        setting.update( # rubocop:disable Rails/SaveBang -- We need to test validity in the subject
          product_analytics_configurator_connection_string: 'https://test.com',
          product_analytics_data_collector_host: 'https://test.net',
          cube_api_base_url: 'https://test.org',
          cube_api_key: 'thisisnotasecret'
        )
      end

      it { is_expected.to be_valid }
    end

    context 'when setting no values' do
      before do
        setting.update( # rubocop:disable Rails/SaveBang -- We need to test validity in the subject
          product_analytics_configurator_connection_string: nil,
          product_analytics_data_collector_host: nil,
          cube_api_base_url: nil,
          cube_api_key: nil
        )
      end

      it { is_expected.to be_valid }
    end

    context 'when setting some values' do
      before do
        setting.update( # rubocop:disable Rails/SaveBang -- We need to test validity in the subject
          product_analytics_configurator_connection_string: nil,
          product_analytics_data_collector_host: 'https://test.net',
          cube_api_base_url: 'https://test.org',
          cube_api_key: 'thisisnotasecret'
        )
      end

      it { is_expected.not_to be_valid }
    end
  end

  describe '.duo_features_set' do
    let_it_be(:setting_1) { create(:project_setting, duo_features_enabled: true) }
    let_it_be(:setting_2) { create(:project_setting, duo_features_enabled: false) }

    subject { described_class.duo_features_set(true) }

    it { is_expected.to contain_exactly(setting_1) }
  end

  describe 'validations' do
    context 'when enabling only_mirror_protected_branches and mirror_branch_regex' do
      it 'is invalid' do
        project = build(:project, only_mirror_protected_branches: true)
        setting = build(:project_setting, project: project, mirror_branch_regex: 'text')

        expect(setting).not_to be_valid
      end
    end

    context 'when disable only_mirror_protected_branches and enable mirror_branch_regex' do
      let_it_be(:project) { build(:project, only_mirror_protected_branches: false) }

      it 'is valid' do
        setting = build(:project_setting, project: project, mirror_branch_regex: 'test')

        expect(setting).to be_valid
      end

      it 'is invalid with invalid regex' do
        setting = build(:project_setting, project: project, mirror_branch_regex: '\\')

        expect(setting).not_to be_valid
      end
    end
  end

  describe '#presence_of_merge_request_title_regex_settings' do
    subject(:project_setting) do
      build(:project_setting, merge_request_title_regex: regex,
        merge_request_title_regex_description: description)
    end

    let(:regex) { '/aaa/' }
    let(:description) { 'Must be aaa' }

    context 'when merge_request_title_regex_check license is available' do
      before do
        stub_licensed_features(merge_request_title_regex_check: true)
      end

      context 'when only the regex is set' do
        let(:description) { nil }

        it 'is not valid' do
          expect(project_setting).not_to be_valid
          expect(project_setting.errors[:merge_request_title_regex])
            .to include("and regex description must be either both set, or neither.")
          expect(project_setting.errors[:merge_request_title_regex_description])
            .to include("and regex must be either both set, or neither.")
        end
      end

      context 'when only the description is set' do
        let(:regex) { nil }

        it 'is not valid' do
          expect(project_setting).not_to be_valid
          expect(project_setting.errors[:merge_request_title_regex])
            .to include("and regex description must be either both set, or neither.")
          expect(project_setting.errors[:merge_request_title_regex_description])
            .to include("and regex must be either both set, or neither.")
        end
      end

      context 'when neither are set' do
        let(:regex) { nil }
        let(:description) { nil }

        it 'is valid' do
          expect(project_setting).to be_valid
        end
      end

      context 'when both are set' do
        it 'is valid' do
          expect(project_setting).to be_valid
        end
      end
    end

    context 'when merge_request_title_regex_check license is not available' do
      before do
        stub_licensed_features(merge_request_title_regex_check: false)
      end

      context 'when only the regex is set' do
        let(:description) { nil }

        it 'is valid' do
          expect(project_setting).to be_valid
        end
      end
    end
  end

  describe '#enqueue_auto_merge_workers' do
    let_it_be(:project) { create(:project) }
    let(:project_setting) { create(:project_setting, project: project) }

    context 'when the project setting is created' do
      it 'does not enqueue the worker' do
        expect(AutoMergeProcessWorker).not_to receive(:perform_async)

        create(:project_setting, project: create(:project))
      end
    end

    context 'when merge_request_title_regex_check license is available' do
      before do
        stub_licensed_features(merge_request_title_regex_check: true)
      end

      it 'enqueues the worker when the regex is updated' do
        expect(AutoMergeProcessWorker).to receive(:perform_async).with({ 'project_id' => project.id })

        project_setting.update!(merge_request_title_regex_description: '1', merge_request_title_regex: '/asa/')
      end

      context 'when regex is updated with the same value' do
        it 'enqueues the worker only once' do
          expect(AutoMergeProcessWorker).to receive(:perform_async).with({ 'project_id' => project.id }).once

          project_setting.update!(merge_request_title_regex_description: '1', merge_request_title_regex: '/asa/')
          project_setting.update!(merge_request_title_regex_description: '1', merge_request_title_regex: '/asa/')
        end
      end

      context 'when the regex is not updated' do
        it 'does not enqueue the worker' do
          expect(AutoMergeProcessWorker).not_to receive(:perform_async)

          project_setting.update!(merge_commit_template: '/asa/')
        end
      end
    end

    context 'when merge_request_title_regex_check license is not available' do
      before do
        stub_licensed_features(merge_request_title_regex_check: false)
      end

      it 'does not enqueue the worker' do
        expect(AutoMergeProcessWorker).not_to receive(:perform_async)

        project_setting.update!(merge_request_title_regex_description: '1', merge_request_title_regex: '/asa/')
      end
    end
  end

  describe '#duo_features_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute', settings_attribute_name: :duo_features_enabled
  end

  describe '#ai_audit_events_storage_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :ai_audit_events_storage_enabled
  end

  describe '#ai_governance_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :ai_governance_enabled
  end

  describe '#ai_agent_governance_enforcement' do
    let_it_be_with_reload(:parent_group) { create(:group) }
    let_it_be_with_reload(:group) { create(:group, parent: parent_group) }
    let_it_be_with_reload(:project) { create(:project, group: group) }

    let(:project_setting) { project.project_setting }

    it 'defaults to off' do
      expect(project_setting.read_attribute(:ai_agent_governance_enforcement)).to eq(0)
    end

    it 'reads the stored value, not a group value that has not cascaded yet' do
      project_setting.save!
      group.namespace_settings.update_column(:ai_agent_governance_enforcement, 2)

      expect(project_setting.reload.ai_agent_governance_enforcement).to eq(0)
    end

    it 'uses the group value when a group locks it' do
      project_setting.update!(ai_agent_governance_enforcement: 0)
      parent_group.namespace_settings.update!(
        ai_agent_governance_enforcement: 2, lock_ai_agent_governance_enforcement: true
      )
      project_setting.clear_memoization(:ai_agent_governance_enforcement)
      project_setting.clear_memoization(:ai_agent_governance_enforcement_locked_ancestor)

      expect(project_setting.ai_agent_governance_enforcement).to eq(2)
    end

    it 'uses the instance value over explicit group and project values when the instance locks it' do
      group.namespace_settings.update!(ai_agent_governance_enforcement: 0)
      project_setting.update!(ai_agent_governance_enforcement: 0)
      stub_application_setting(ai_agent_governance_enforcement: 2, lock_ai_agent_governance_enforcement: true)

      expect(project_setting.reload.ai_agent_governance_enforcement).to eq(2)
    end

    it 'does not allow the project value to change when a group locks it' do
      parent_group.namespace_settings.update!(
        ai_agent_governance_enforcement: 2, lock_ai_agent_governance_enforcement: true
      )
      project_setting.ai_agent_governance_enforcement = 1

      expect(project_setting).not_to be_valid
      expect(project_setting.errors[:ai_agent_governance_enforcement]).to be_present
    end

    it 'rejects an unknown mode' do
      project_setting.ai_agent_governance_enforcement = 3

      expect(project_setting).not_to be_valid
      expect(project_setting.errors[:ai_agent_governance_enforcement]).to be_present
    end

    it 'does not validate the mode when it is unchanged' do
      project_setting.save!
      project_setting.update_column(:ai_agent_governance_enforcement, 3)

      expect(described_class.find_by(project_id: project.id)).to be_valid
    end

    context 'when the value is not an integer' do
      where(:value) { ['enforce', 'dry_run', true, false, '', ' '] }

      with_them do
        it 'rejects it instead of casting it to a mode' do
          project_setting.ai_agent_governance_enforcement = value

          expect(project_setting).not_to be_valid
          expect(project_setting.errors[:ai_agent_governance_enforcement]).to be_present
        end
      end
    end

    context 'when the project is in a personal namespace' do
      let_it_be_with_reload(:personal_project) { create(:project) }

      let(:project_setting) { personal_project.project_setting }

      it 'reads the stored value, not an unlocked instance value' do
        project_setting.save!
        stub_application_setting(ai_agent_governance_enforcement: 2)

        expect(project_setting.reload.ai_agent_governance_enforcement).to eq(0)
      end

      it 'uses the instance value when the instance locks it' do
        project_setting.save!
        stub_application_setting(ai_agent_governance_enforcement: 2, lock_ai_agent_governance_enforcement: true)

        expect(project_setting.reload.ai_agent_governance_enforcement).to eq(2)
      end
    end
  end

  describe '#spp_repository_pipeline_access' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :spp_repository_pipeline_access
  end

  describe '#model_prompt_cache_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :model_prompt_cache_enabled
  end

  describe '#auto_duo_code_review_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :auto_duo_code_review_enabled
  end

  describe '#auto_duo_code_review_on_push_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :auto_duo_code_review_on_push_enabled
  end

  describe '#duo_code_review_decisions_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :duo_code_review_decisions_enabled
  end

  describe '#duo_code_review_approval_counts_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :duo_code_review_approval_counts_enabled
  end

  describe '#duo_remote_flows_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :duo_remote_flows_enabled
  end

  describe '#duo_foundational_flows_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :duo_foundational_flows_enabled
  end

  describe '#duo_scheduled_triggers_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :duo_scheduled_triggers_enabled
  end

  describe '#tool_approval_for_session_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :tool_approval_for_session_enabled
  end

  describe '#duo_auto_mode_enabled' do
    it_behaves_like 'a cascading project setting boolean attribute',
      settings_attribute_name: :duo_auto_mode_enabled
  end

  describe '#enabled_foundational_flows' do
    let(:setting) { build(:project_setting) }

    it 'accepts an array of integers' do
      setting.enabled_foundational_flows = [1, 2, 3]

      expect(setting.enabled_foundational_flows).to match_array([1, 2, 3])
    end

    it 'defaults to nil' do
      new_setting = described_class.new

      expect(new_setting.enabled_foundational_flows).to be_nil
    end

    it 'accepts nil' do
      setting.enabled_foundational_flows = nil

      expect(setting.enabled_foundational_flows).to be_nil
    end

    it 'accepts an empty array' do
      setting.enabled_foundational_flows = []

      expect(setting.enabled_foundational_flows).to eq([])
    end
  end

  describe '#reviewer_auto_assignment_available?', feature_category: :code_review_workflow do
    let_it_be(:project) { create(:project) }
    let(:project_setting) { project.project_setting }

    context 'when code_owners license is enabled' do
      before do
        stub_licensed_features(code_owners: true)
      end

      it 'returns true' do
        expect(project_setting.reviewer_auto_assignment_available?).to be(true)
      end
    end

    context 'when code_owners license is not available' do
      before do
        stub_licensed_features(code_owners: false)
      end

      it 'returns false' do
        expect(project_setting.reviewer_auto_assignment_available?).to be(false)
      end
    end
  end

  describe '#reviewer_auto_assignment_enabled?', feature_category: :code_review_workflow do
    let_it_be(:project) { create(:project) }
    let(:project_setting) { project.project_setting }

    context 'when strategy is disabled' do
      before do
        stub_licensed_features(code_owners: true)
        project_setting.update!(reviewer_assignment_strategy: 'disabled')
      end

      it 'returns false' do
        expect(project_setting.reviewer_auto_assignment_enabled?).to be(false)
      end
    end

    context 'when strategy is code_owners' do
      before do
        stub_licensed_features(code_owners: true)
        project_setting.update!(reviewer_assignment_strategy: 'code_owners')
      end

      it 'returns true' do
        expect(project_setting.reviewer_auto_assignment_enabled?).to be(true)
      end
    end

    context 'when strategy is the retired dap_powered value' do
      before do
        stub_licensed_features(code_owners: true)
        project_setting.update!(reviewer_assignment_strategy: 'dap_powered')
      end

      it 'returns false' do
        expect(project_setting.reviewer_auto_assignment_enabled?).to be(false)
      end
    end
  end

  describe '#dap_session_tracking_available?', feature_category: :source_code_management do
    let_it_be(:project) { create(:project) }
    let(:project_setting) { project.project_setting }

    context 'when feature flag, license, and duo features are all enabled' do
      before do
        stub_licensed_features(ai_workflows: true)
        project.project_setting.update!(duo_features_enabled: true)
      end

      it 'returns true' do
        expect(project_setting.dap_session_tracking_available?).to be(true)
      end
    end

    context 'when feature flag is disabled' do
      before do
        stub_feature_flags(dap_session_commit_tracking: false)
        stub_licensed_features(ai_workflows: true)
        project.project_setting.update!(duo_features_enabled: true)
      end

      it 'returns false' do
        expect(project_setting.dap_session_tracking_available?).to be(false)
      end
    end

    context 'when license is not available' do
      before do
        stub_licensed_features(ai_workflows: false)
        project.project_setting.update!(duo_features_enabled: true)
      end

      it 'returns false' do
        expect(project_setting.dap_session_tracking_available?).to be(false)
      end
    end

    context 'when duo features are disabled' do
      before do
        stub_licensed_features(ai_workflows: true)
        project.project_setting.update!(duo_features_enabled: false)
      end

      it 'returns false' do
        expect(project_setting.dap_session_tracking_available?).to be(false)
      end
    end
  end

  describe '#dap_session_tracking_enabled?', feature_category: :source_code_management do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:project) { create(:project) }
    let(:project_setting) { project.project_setting }

    subject { project_setting.dap_session_tracking_enabled? }

    where(:feature_flag, :license, :duo_features, :column_value, :expected) do
      true  | true  | true  | true  | true
      true  | true  | true  | false | false
      false | true  | true  | true  | false
      true  | false | true  | true  | false
      true  | true  | false | true  | false
    end

    with_them do
      before do
        stub_feature_flags(dap_session_commit_tracking: feature_flag)
        stub_licensed_features(ai_workflows: license)
        project_setting.update!(duo_features_enabled: duo_features, dap_session_tracking_enabled: column_value)
      end

      it { is_expected.to be expected }
    end
  end

  describe '#dap_session_tracking_enabled column' do
    it 'defaults to false' do
      project_setting = described_class.new

      expect(project_setting.dap_session_tracking_enabled).to be(false)
    end
  end
end
