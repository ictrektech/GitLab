# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TreeHelper, feature_category: :source_code_management do
  include Devise::Test::ControllerHelpers
  let_it_be(:project) { create(:project, :small_repo) }
  let(:repository) { project.repository }
  let(:sha) { 'c1c67abbaf91f624347bb3ae96eabe3a1b742478' }

  let_it_be_with_reload(:user) { create(:user) }

  before do
    allow(Current).to receive(:organization).and_return(project.organization)
  end

  describe '#tree_edit_branch' do
    let(:ref) { 'main' }

    before do
      allow(helper).to receive(:patch_branch_name).and_return('patch-1')
    end

    it 'returns nil when cannot edit tree' do
      allow(helper).to receive(:can_edit_tree?).and_return(false)
      expect(helper.tree_edit_branch(project, ref)).to be_nil
    end

    it 'returns the patch branch name when can edit tree' do
      allow(helper).to receive(:can_edit_tree?).and_return(true)
      expect(helper.tree_edit_branch(project, ref)).to eq('patch-1')
    end
  end

  describe '#breadcrumb_data_attributes' do
    let(:ref) { 'main' }
    let(:base_attributes) do
      {
        selected_branch: ref,
        can_push_code: 'false',
        can_push_to_branch: 'false',
        can_collaborate: 'false',
        new_blob_path: project_new_blob_path(project, ref),
        upload_path: project_create_blob_path(project, ref),
        new_dir_path: project_create_dir_path(project, ref),
        new_branch_path: new_project_branch_path(project),
        new_tag_path: new_project_tag_path(project),
        can_edit_tree: 'false'
      }
    end

    before do
      helper.instance_variable_set(:@project, project)
      helper.instance_variable_set(:@ref, ref)
      allow(helper).to receive_messages(
        selected_branch: ref,
        current_user: user,
        can?: false,
        user_access: instance_double(Gitlab::UserAccess, can_push_to_branch?: false),
        can_collaborate_with_project?: false,
        can_edit_tree?: false
      )
    end

    it 'returns a list of breadcrumb attributes' do
      expect(helper.breadcrumb_data_attributes).to eq(base_attributes)
    end

    it 'prefers the passed project and ref over instance variables' do
      helper.instance_variable_set(:@project, build_stubbed(:project))
      helper.instance_variable_set(:@ref, 'other-ref')

      expect(helper.breadcrumb_data_attributes(project, ref)).to eq(base_attributes)
    end
  end

  describe '#compare_path' do
    before do
      helper.instance_variable_set(:@project, project)
      helper.instance_variable_set(:@ref, sha)
    end

    context 'when ref is blank' do
      it 'returns nil when root_ref matches ref' do
        expect(helper.compare_path(project, repository, '')).to be_nil
      end

      it 'returns nil when ref is nil' do
        expect(helper.compare_path(project, repository, nil)).to be_nil
      end
    end

    context 'when ref is present' do
      it 'returns compare path when ref differs from root_ref' do
        expected_path = project_compare_index_path(project, from: 'master', to: 'feature-branch')
        expect(helper.compare_path(project, repository, 'feature-branch')).to eq(expected_path)
      end

      it 'returns nil when ref matches root_ref' do
        allow(repository).to receive(:root_ref).and_return('main')
        expect(helper.compare_path(project, repository, 'main')).to be_nil
      end

      it 'handles refs with special characters' do
        expected_path = project_compare_index_path(project, from: 'master', to: 'feature/branch-1')
        expect(helper.compare_path(project, repository, 'feature/branch-1')).to eq(expected_path)
      end
    end
  end

  describe '#vue_tree_header_app_data' do
    before do
      helper.instance_variable_set(:@project, project)
      helper.instance_variable_set(:@ref, sha)
      allow(helper).to receive_messages(
        can?: false,
        can_collaborate_with_project?: true,
        user_access: instance_double(Gitlab::UserAccess, can_push_to_branch?: false),
        current_user: user,
        ssh_enabled?: true,
        http_enabled?: true,
        show_xcode_link?: false
      )
    end

    subject { helper.vue_tree_header_app_data(project, repository, sha, 'heads') }

    it 'returns a list of attributes related to the project' do
      is_expected.to include(
        project_id: project.id,
        ref: sha,
        ref_type: '',
        root_ref: repository.root_ref,
        breadcrumbs: helper.breadcrumb_data_attributes,
        project_root_path: project_path(project),
        project_path: project.full_path,
        compare_path: project_compare_index_path(project, from: repository&.root_ref, to: sha),
        web_ide_button_options: helper.repository_header_web_ide_button_options(nil),
        ssh_url: ssh_clone_url_to_repo(project),
        http_url: http_clone_url_to_repo(project),
        xcode_url: '',
        download_links: helper.download_links(project, sha, "#{project.path}-#{sha.tr('/', '-')}", 'heads').to_json,
        escaped_ref: sha
      )
    end

    context 'when ssh is disabled' do
      before do
        allow(helper).to receive(:ssh_enabled?).and_return(false)
      end

      it 'does not include ssh_url' do
        expect(subject[:ssh_url]).to be_empty
      end
    end

    context 'when http is disabled' do
      before do
        allow(helper).to receive(:http_enabled?).and_return(false)
      end

      it 'does not include http_url' do
        expect(subject[:http_url]).to be_empty
      end
    end

    context 'when project is empty' do
      before do
        allow(project).to receive(:empty_repo?).and_return(true)
      end

      it 'returns an empty JSON array for download_links' do
        expect(subject[:download_links]).to eq('[]')
      end
    end

    it 'includes the custom Code dropdown clients' do
      stub_feature_flags(custom_code_dropdown_clients: true)
      stub_application_setting(code_dropdown_custom_clients: [
        { 'name' => 'VSCodium', 'http_url_template' => 'vscodium://vscode.git/clone?url={url}' }
      ])

      parsed = Gitlab::Json.parse(subject[:custom_code_dropdown_clients])

      expect(parsed.pluck('name')).to eq(['VSCodium'])
    end
  end

  describe '#vue_file_list_data' do
    let(:ref) { sha }

    before do
      helper.instance_variable_set(:@ref_type, 'heads')
      allow(helper).to receive(:current_user).and_return(user)
    end

    context 'when there is no ignore revs file' do
      let(:repo_double) { instance_double(Repository, ignore_revs_file_blob: nil) }

      before do
        allow(project).to receive(:repository).and_return(repo_double)
      end

      it 'includes has_revs_file as false' do
        expect(helper.vue_file_list_data(project, ref)).to include(
          has_revs_file: 'false'
        )
      end
    end

    context 'when there is an ignore revs file' do
      let(:ignore_revs_blob) { instance_double(Gitlab::Git::Blob) }
      let(:repo_double) { instance_double(Repository, ignore_revs_file_blob: ignore_revs_blob) }

      before do
        allow(project).to receive(:repository).and_return(repo_double)
      end

      it 'includes has_revs_file as true' do
        expect(helper.vue_file_list_data(project, ref)).to include(
          has_revs_file: 'true'
        )
      end
    end

    it 'returns a list of attributes related to the project' do
      expect(helper.vue_file_list_data(project, sha)).to include(
        project_path: project.full_path,
        project_short_path: project.path,
        ref: sha,
        escaped_ref: sha,
        full_name: project.name_with_namespace,
        ref_type: 'heads',
        can_download_code: 'false'
      )
    end

    context 'when a user can download code' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :download_code, project).and_return(true)
      end

      it 'returns true for `can_download_code` value' do
        expect(helper.vue_file_list_data(project, sha)).to include(
          can_download_code: 'true'
        )
      end
    end
  end

  describe '#repository_single_vue_app_enabled?' do
    it 'returns true when the flag is enabled for the project' do
      stub_feature_flags(repository_single_vue_app: project)

      expect(helper.repository_single_vue_app_enabled?(project)).to be(true)
    end

    it 'returns false when the flag is disabled' do
      stub_feature_flags(repository_single_vue_app: false)

      expect(helper.repository_single_vue_app_enabled?(project)).to be(false)
    end
  end

  describe '#vue_repository_app_data' do
    let(:ref) { 'master' }
    let(:blob) { nil }
    let(:fork_keys) do
      %i[source_name source_path source_default_branch can_sync_branch ahead_compare_path
        behind_compare_path create_mr_path view_mr_path]
    end

    before do
      helper.instance_variable_set(:@project, project)
      helper.instance_variable_set(:@ref, ref)
      allow(helper).to receive_messages(
        can?: false,
        can_collaborate_with_project?: true,
        user_access: instance_double(Gitlab::UserAccess, can_push_to_branch?: false),
        current_user: user,
        ssh_enabled?: true,
        http_enabled?: true,
        show_xcode_link?: false
      )
    end

    subject(:data) { helper.vue_repository_app_data(project, repository, ref, 'heads', blob: blob) }

    it 'returns the deduplicated attributes' do
      is_expected.to include(
        project_id: project.id,
        project_path: project.full_path,
        project_short_path: project.path,
        project_root_path: project_path(project),
        full_name: project.name_with_namespace,
        resource_id: project.to_global_id,
        ref: ref,
        escaped_ref: ref,
        ref_type: 'heads',
        root_ref: repository.root_ref,
        history_link: project_commits_path(project, ref),
        can_download_code: 'false',
        has_revs_file: 'false',
        compare_path: helper.compare_path(project, repository, ref),
        ssh_url: ssh_clone_url_to_repo(project),
        http_url: http_clone_url_to_repo(project),
        xcode_url: '',
        download_links: Gitlab::Json.generate(helper.download_links(project, ref, "#{project.path}-#{ref}", 'heads')),
        web_ide_button_options: helper.repository_header_web_ide_button_options(nil),
        can_view_branch_rules: 'false',
        branch_rules_path: project_settings_repository_path(project, anchor: 'branch-rules')
      )
    end

    it 'does not emit duplicated ref keys' do
      expect(data.keys).not_to include(:selected_branch, :original_branch, :branch)
      expect(data[:breadcrumbs]).not_to have_key(:selected_branch)
      expect(data[:breadcrumbs]).to eq(helper.breadcrumb_data_attributes.except(:selected_branch))
    end

    it 'does not include blob-only keys' do
      expect(data.keys).not_to include(:blob_path, :is_binary)
    end

    it 'derives project-scoped values from the project argument, not @project' do
      helper.instance_variable_set(:@project, build_stubbed(:project))
      helper.instance_variable_set(:@ref, 'other-ref')
      allow(helper).to receive(:repository_header_web_ide_button_options).and_return('{}')

      expect(data).to include(
        branch_rules_path: project_settings_repository_path(project, anchor: 'branch-rules')
      )
      expect(data[:breadcrumbs]).to include(
        new_blob_path: project_new_blob_path(project, ref),
        new_branch_path: new_project_branch_path(project)
      )
    end

    describe 'suggested_target_branch' do
      it 'uses @branch_name when set' do
        helper.instance_variable_set(:@branch_name, 'my-target-branch')

        expect(data).to include(ref: ref, suggested_target_branch: 'my-target-branch')
      end

      it 'uses the generated patch branch name when the user can edit the tree' do
        allow(helper).to receive(:can_edit_tree?).and_return(true)
        allow(helper).to receive(:patch_branch_name).with(ref).and_return('user-master-patch-12345')

        expect(data).to include(ref: ref, suggested_target_branch: 'user-master-patch-12345')
      end

      it 'is nil when the user cannot edit the tree' do
        allow(helper).to receive(:can_edit_tree?).and_return(false)

        expect(data).to include(ref: ref, suggested_target_branch: nil)
      end
    end

    context 'with a blob' do
      let(:blob) { project.repository.blob_at(ref, 'test.txt') }

      it 'includes blob-only keys and builds web IDE options from the blob' do
        is_expected.to include(
          blob_path: blob.path,
          is_binary: blob.binary?.to_s,
          web_ide_button_options: helper.repository_header_web_ide_button_options(blob)
        )
      end
    end

    context 'when the project has no visible fork source' do
      it 'does not include fork keys' do
        expect(data.keys).not_to include(*fork_keys)
      end
    end

    context 'when the project has a visible fork source' do
      let(:fork_data) do
        fork_keys.index_with { |key| "#{key}-value" }.merge(project_path: 'fork/path', selected_branch: ref)
      end

      before do
        allow(helper).to receive(:vue_fork_divergence_data).with(project, ref).and_return(fork_data)
      end

      it 'includes fork keys without duplicating project_path or ref' do
        is_expected.to include(fork_data.except(:project_path, :selected_branch))
        expect(data[:project_path]).to eq(project.full_path)
        expect(data.keys).not_to include(:selected_branch)
      end
    end

    context 'when ssh is disabled' do
      before do
        allow(helper).to receive(:ssh_enabled?).and_return(false)
      end

      it 'does not include ssh data' do
        is_expected.to include(ssh_url: '', show_no_ssh_key_message: '', user_settings_ssh_keys_path: '')
      end
    end

    context 'when http is disabled' do
      before do
        allow(helper).to receive(:http_enabled?).and_return(false)
      end

      it 'does not include http_url' do
        expect(data[:http_url]).to be_empty
      end
    end

    context 'when Xcode link should be shown' do
      before do
        allow(helper).to receive(:show_xcode_link?).and_return(true)
      end

      it 'includes xcode_url' do
        expect(data[:xcode_url]).to eq(helper.xcode_uri_to_repo(project))
      end
    end

    context 'with a ref containing special characters' do
      let(:ref) { 'feature/#branch' }

      it 'escapes the ref' do
        is_expected.to include(ref: ref, escaped_ref: 'feature/%23branch')
      end
    end
  end

  describe '#code_dropdown_ide_data' do
    before do
      helper.instance_variable_set(:@project, project)
      helper.instance_variable_set(:@ref, sha)
      allow(helper).to receive_messages(
        current_user: user,
        show_web_ide_button?: true,
        show_gitpod_button?: false,
        web_ide_url: "/-/ide/project/#{project.full_path}/edit/#{sha}",
        gitpod_url: ''
      )
    end

    subject { helper.code_dropdown_ide_data }

    it 'returns a hash with IDE-related attributes' do
      expect(subject).to include(
        gitpod_enabled: false,
        show_web_ide_button: true,
        show_gitpod_button: false,
        web_ide_url: "/-/ide/project/#{project.full_path}/edit/#{sha}",
        gitpod_url: ''
      )
    end

    context 'when user has ona enabled' do
      before do
        user.gitpod_enabled = true
      end

      it 'includes gitpod_enabled: true' do
        expect(subject).to include(gitpod_enabled: true)
      end
    end

    context 'when there is no current user' do
      before do
        allow(helper).to receive(:current_user).and_return(nil)
      end

      it 'includes gitpod_enabled: false' do
        expect(subject).to include(gitpod_enabled: false)
      end
    end

    context 'when web IDE button is not shown' do
      before do
        allow(helper).to receive(:show_web_ide_button?).and_return(false)
      end

      it 'includes show_web_ide_button: false' do
        expect(subject).to include(show_web_ide_button: false)
      end
    end

    context 'when gitpod button is shown' do
      before do
        allow(helper).to receive(:show_gitpod_button?).and_return(true)
      end

      it 'includes show_gitpod_button: true' do
        expect(subject).to include(show_gitpod_button: true)
      end
    end
  end

  describe '.patch_branch_name' do
    before do
      allow(helper).to receive(:current_user).and_return(user)
    end

    subject { helper.patch_branch_name('master') }

    it 'returns a patch branch name' do
      freeze_time do
        epoch = Time.now.strftime('%s%L').last(5)

        expect(subject).to eq "#{user.username}-master-patch-#{epoch}"
      end
    end

    context 'without a current_user' do
      let(:user) { nil }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end
  end

  describe '#compact_code_dropdown_data' do
    let(:ref) { 'main' }
    let(:archive_prefix) { "#{project.path}-#{ref}" }

    before do
      helper.instance_variable_set(:@project, project)
      helper.instance_variable_set(:@ref, ref)
      allow(helper).to receive_messages(
        current_user: user,
        ssh_enabled?: true,
        http_enabled?: true,
        show_xcode_link?: false,
        code_dropdown_ide_data: {
          gitpod_enabled: false,
          show_web_ide_button: true,
          show_gitpod_button: false,
          web_ide_url: "/-/ide/project/#{project.full_path}/edit/#{ref}",
          gitpod_url: ''
        }
      )
    end

    subject { helper.compact_code_dropdown_data(project, ref, 'heads') }

    it 'returns a hash with the expected keys' do
      expected_keys = [
        :ssh_url, :http_url, :xcode_url,
        :ide_data, :directory_download_links,
        :show_no_ssh_key_message, :user_settings_ssh_keys_path,
        :custom_code_dropdown_clients
      ]
      expect(subject.keys).to match_array(expected_keys)
    end

    describe ':custom_code_dropdown_clients' do
      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(custom_code_dropdown_clients: false)
        end

        it 'is an empty JSON array' do
          expect(subject[:custom_code_dropdown_clients]).to eq('[]')
        end
      end

      context 'when the feature flag is enabled' do
        let(:vscodium_entry) do
          {
            'name' => 'VSCodium',
            'ssh_url_template' => 'vscodium://vscode.git/clone?url={url}',
            'http_url_template' => 'vscodium://vscode.git/clone?url={url}'
          }
        end

        before do
          stub_feature_flags(custom_code_dropdown_clients: true)
          stub_application_setting(code_dropdown_custom_clients: [vscodium_entry])
        end

        it 'serializes admin entries with substituted URLs' do
          parsed = Gitlab::Json.parse(subject[:custom_code_dropdown_clients])
          expect(parsed.first['name']).to eq('VSCodium')
          expect(parsed.first['ssh_url']).to include('vscodium://vscode.git/clone?url=')
          expect(parsed.first['http_url']).to include('vscodium://vscode.git/clone?url=')
        end

        it 'percent-encodes the clone URL into the placeholder' do
          allow(helper).to receive(:http_clone_url_to_repo).and_return('https://example.com/foo bar?x=1')
          parsed = Gitlab::Json.parse(subject[:custom_code_dropdown_clients])
          expect(parsed.first['http_url']).to include('foo%20bar')
          expect(parsed.first['http_url']).to include('%3F')
        end

        # #security -- a stored value can skip model validation (for example a direct database
        # write), and these links render unsanitized, so the helper must drop unsafe URLs itself.
        context 'with a template whose scheme would be refused on save' do
          where(:template) do
            [
              'javascript:alert(1)//{url}',
              'JaVaScRiPt:alert(1)//{url}',
              'data:text/html,<script>alert(1)</script>?{url}',
              ' javascript:alert(1)//{url}',
              'no-scheme/{url}'
            ]
          end

          with_them do
            it 'drops that URL and keeps the safe one' do
              stub_application_setting(code_dropdown_custom_clients: [
                vscodium_entry.merge('http_url_template' => template)
              ])

              parsed = Gitlab::Json.parse(subject[:custom_code_dropdown_clients]).first

              expect(parsed['http_url']).to be_nil
              expect(parsed['ssh_url']).to start_with('vscodium://')
            end
          end
        end

        it 'skips stored entries that are not objects' do
          stub_application_setting(code_dropdown_custom_clients: ['junk', vscodium_entry])

          parsed = Gitlab::Json.parse(subject[:custom_code_dropdown_clients])
          expect(parsed.pluck('name')).to eq(['VSCodium'])
        end

        it 'leaves the URL nil when the entry has no template for it' do
          stub_application_setting(code_dropdown_custom_clients: [vscodium_entry.except('http_url_template')])

          parsed = Gitlab::Json.parse(subject[:custom_code_dropdown_clients]).first
          expect(parsed['http_url']).to be_nil
          expect(parsed['ssh_url']).to start_with('vscodium://')
        end

        it 'skips an entry left with no usable URL when a protocol is disabled' do
          allow(helper).to receive(:ssh_enabled?).and_return(false)
          stub_application_setting(code_dropdown_custom_clients: [
            vscodium_entry.except('http_url_template'), vscodium_entry.merge('name' => 'Fork')
          ])

          parsed = Gitlab::Json.parse(subject[:custom_code_dropdown_clients])

          expect(parsed.pluck('name')).to eq(['Fork'])
          expect(parsed.first['ssh_url']).to be_nil
        end

        it 'skips an entry whose only template has a blocked scheme' do
          stub_application_setting(code_dropdown_custom_clients: [
            { 'name' => 'Bad', 'http_url_template' => 'javascript:alert(1)//{url}' }, vscodium_entry
          ])

          parsed = Gitlab::Json.parse(subject[:custom_code_dropdown_clients])

          expect(parsed.pluck('name')).to eq(['VSCodium'])
        end
      end
    end

    it 'includes SSH URL when SSH is enabled' do
      expect(subject[:ssh_url]).to eq(ssh_clone_url_to_repo(project))
    end

    it 'includes HTTP URL when HTTP is enabled' do
      expect(subject[:http_url]).to eq(http_clone_url_to_repo(project))
    end

    it 'includes empty Xcode URL when Xcode link is not shown' do
      expect(subject[:xcode_url]).to eq('')
    end

    context 'when current user has a namespace' do
      before do
        allow(user).to receive(:namespace).and_return(build_stubbed(:namespace))
      end

      it 'includes IDE data as JSON' do
        ide_data = {
          gitpod_enabled: false,
          show_web_ide_button: true,
          show_gitpod_button: false,
          web_ide_url: "/-/ide/project/#{project.full_path}/edit/#{ref}",
          gitpod_url: ''
        }
        expect(subject[:ide_data]).to eq(ide_data.to_json)
      end
    end

    context 'when current user does not have a namespace' do
      before do
        allow(user).to receive(:namespace).and_return(nil)
      end

      it 'returns empty IDE data' do
        expect(subject[:ide_data]).to eq('')
      end
    end

    context 'when there is no current user' do
      before do
        allow(helper).to receive(:current_user).and_return(nil)
      end

      it 'returns empty IDE data' do
        expect(subject[:ide_data]).to eq('')
      end
    end

    context 'for repository' do
      context 'when it is not empty' do
        before do
          allow(project).to receive(:empty_repo?).and_return(false)
        end

        it 'includes directory download links as JSON' do
          expected_links = helper.download_links(project, ref, archive_prefix, 'heads').to_json
          expect(subject[:directory_download_links]).to eq(expected_links)
        end
      end

      context 'when it is empty' do
        before do
          allow(project).to receive(:empty_repo?).and_return(true)
        end

        it 'returns an empty JSON array for directory download links' do
          expect(subject[:directory_download_links]).to eq('[]')
        end
      end
    end

    context 'when SSH is disabled' do
      before do
        allow(helper).to receive(:ssh_enabled?).and_return(false)
      end

      it 'returns empty SSH URL' do
        expect(subject[:ssh_url]).to eq('')
      end
    end

    context 'when HTTP is disabled' do
      before do
        allow(helper).to receive(:http_enabled?).and_return(false)
      end

      it 'returns empty HTTP URL' do
        expect(subject[:http_url]).to eq('')
      end
    end

    context 'when Xcode link should be shown' do
      before do
        allow(helper).to receive(:show_xcode_link?).and_return(true)
        allow(helper).to receive(:xcode_uri_to_repo).with(project).and_return('xcode://example.com/project.git')
      end

      it 'includes Xcode URL' do
        expect(subject[:xcode_url]).to eq('xcode://example.com/project.git')
      end
    end

    context 'when ref is nil' do
      let(:ref) { nil }

      before do
        allow(project).to receive(:empty_repo?).and_return(false)
      end

      it 'uses empty string for archive prefix' do
        expect(helper).to receive(:download_links).with(project, nil, '', 'heads').and_return([])

        subject
      end
    end
  end
end
