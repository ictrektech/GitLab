# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TreeHelper, feature_category: :source_code_management do
  include Devise::Test::ControllerHelpers
  include FakeBlobHelpers

  let_it_be(:project) { build_stubbed(:project, :repository) }
  let(:repository) { project.repository }
  let(:sha) { 'c1c67abbaf91f624347bb3ae96eabe3a1b742478' }

  let_it_be(:user) { build_stubbed(:user) }

  describe '#vue_tree_header_app_data' do
    let(:organization) { build_stubbed(:organization) }

    before do
      Current.organization = organization
      helper.instance_variable_set(:@project, project)
      helper.instance_variable_set(:@ref, sha)
    end

    subject { helper.vue_tree_header_app_data(project, repository, sha, 'heads') }

    it 'contains workspace data' do
      expect(helper.vue_tree_header_app_data(project, repository, sha, 'heads')).to include(
        new_workspace_path: new_remote_development_workspace_path,
        organization_id: organization.id
      )
    end

    context 'when alternative_kerberos_url? is true' do
      let(:gitlab_kerberos_url) { Gitlab.config.build_gitlab_kerberos_url }
      let(:repo_kerberos_url) { "#{gitlab_kerberos_url}/#{project.full_path}.git" }

      before do
        allow(helper).to receive(:alternative_kerberos_url?).and_return(true)
      end

      it { is_expected.to include(kerberos_url: repo_kerberos_url) }
    end

    context 'when alternative_kerberos_url? is false' do
      before do
        allow(helper).to receive(:alternative_kerberos_url?).and_return(false)
      end

      it { is_expected.to include(kerberos_url: '') }
    end
  end

  describe '#vue_file_list_data' do
    before do
      project.add_developer(user)
      allow(helper).to receive(:current_user).and_return(user)
      sign_in(user)
    end

    context 'with explain_code_available parameter' do
      using RSpec::Parameterized::TableSyntax

      context 'when current_user is nil' do
        before do
          allow(helper).to receive(:current_user).and_return(nil)
        end

        it 'returns false for explain_code_available' do
          expect(helper.vue_file_list_data(project, sha)).to include(
            explain_code_available: 'false'
          )
        end
      end

      context 'when current_user is present' do
        before do
          stub_feature_flags(dap_external_trigger_usage_billing: flag_enabled)

          if flag_enabled
            allow(user).to receive(:allowed_to_use?).with(:duo_chat).and_return(has_duo_addon)
          else
            duo_chat_instance = instance_double(::Gitlab::Llm::DuoChat)
            allow(::Gitlab::Llm::DuoChat).to receive(:new)
              .with(user: user, container: project)
              .and_return(duo_chat_instance)
            allow(duo_chat_instance).to receive(:enabled_for_container?)
              .and_return(duo_chat_enabled)
          end
        end

        where(:flag_enabled, :has_duo_addon, :duo_chat_enabled, :expected_value) do
          true  | true  | nil   | 'true'
          true  | false | nil   | 'false'
          false | nil   | true  | 'true'
          false | nil   | false | 'false'
        end

        with_them do
          it 'returns correct explain_code_available value' do
            expect(helper.vue_file_list_data(project, sha)).to include(
              explain_code_available: expected_value
            )
          end
        end
      end
    end

    context 'with project attributes' do
      before do
        stub_feature_flags(dap_external_trigger_usage_billing: false)
        duo_chat_instance = instance_double(::Gitlab::Llm::DuoChat)
        allow(::Gitlab::Llm::DuoChat).to receive(:new)
          .with(user: user, container: project)
          .and_return(duo_chat_instance)
        allow(duo_chat_instance).to receive(:enabled_for_container?)
          .and_return(false)
      end

      it 'returns a list of attributes related to the project' do
        expect(helper.vue_file_list_data(project, sha)).to include(
          project_path: project.full_path,
          project_short_path: project.path,
          ref: sha,
          escaped_ref: sha,
          full_name: project.name_with_namespace,
          resource_id: project.to_global_id
        )
      end
    end
  end

  describe '#vue_repository_app_data' do
    let(:organization) { build_stubbed(:organization) }
    let(:blob) { nil }

    before do
      Current.organization = organization
      helper.instance_variable_set(:@project, project)
      helper.instance_variable_set(:@ref, sha)
      allow(helper).to receive_messages(current_user: nil, vue_fork_divergence_data: {})
    end

    subject(:data) { helper.vue_repository_app_data(project, repository, sha, 'heads', blob: blob) }

    it 'merges the EE attributes' do
      is_expected.to include(
        resource_id: project.to_global_id,
        explain_code_available: 'false',
        new_workspace_path: new_remote_development_workspace_path,
        organization_id: organization.id
      )
    end

    context 'when alternative_kerberos_url? is true' do
      before do
        allow(helper).to receive(:alternative_kerberos_url?).and_return(true)
      end

      it { is_expected.to include(kerberos_url: project.kerberos_url_to_repo) }
    end

    context 'when alternative_kerberos_url? is false' do
      before do
        allow(helper).to receive(:alternative_kerberos_url?).and_return(false)
      end

      it { is_expected.to include(kerberos_url: '') }
    end

    context 'without a blob' do
      before do
        allow(helper).to receive(:repository_header_web_ide_button_options).with(nil).and_return('{}')
      end

      it 'uses the tree variants of the EE data' do
        expect(helper).to receive(:tree_explain_code_available?).with(project).and_return(true)
        expect(helper).to receive(:vue_tree_workspace_data).and_call_original
        expect(helper).not_to receive(:blob_explain_code_available?)

        expect(data).to include(explain_code_available: 'true')
      end
    end

    context 'with a blob' do
      let(:blob) { fake_blob(path: 'README.md') }

      before do
        allow(helper).to receive(:repository_header_web_ide_button_options).with(blob).and_return('{}')
      end

      it 'uses the blob variants of the EE data' do
        expect(helper).to receive(:blob_explain_code_available?).with(project).and_return(true)
        expect(helper).to receive(:vue_blob_workspace_data).and_call_original
        expect(helper).not_to receive(:tree_explain_code_available?)

        expect(data).to include(explain_code_available: 'true', blob_path: 'README.md')
      end
    end
  end

  describe '#web_ide_button_data' do
    let(:organization) { build_stubbed(:organization) }

    before do
      Current.organization = organization
      allow(helper).to receive_messages(project_to_use: project, project_ci_pipeline_editor_path: '')
    end

    it 'includes workspace data and project id properties' do
      options = {}

      expect(helper.web_ide_button_data(options)).to include(
        new_workspace_path: new_remote_development_workspace_path,
        project_id: project.id,
        organization_id: organization.id
      )
    end
  end
end
