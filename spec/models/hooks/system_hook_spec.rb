# frozen_string_literal: true

require "spec_helper"

RSpec.describe SystemHook, feature_category: :webhooks do
  let(:default_organization) { build_stubbed(:organization, :default) } # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- instance admin hooks live in the default organization
  let(:other_organization) { build_stubbed(:organization) }

  describe 'auto-disabling' do
    context 'when the hook is in the default organization' do
      it_behaves_like 'a hook that does not get automatically disabled on failure' do
        # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- default organization hooks belong to instance admins
        let_it_be(:organization) { create(:organization, :default) }
        # rubocop:enable Gitlab/RSpec/AvoidCreateDefaultOrganization
        let_it_be_with_reload(:hook) { create(:system_hook, organization: organization) }
        let(:hook_factory) { :system_hook }
        let(:default_factory_arguments) { { organization: organization } }

        def find_hooks
          described_class.all
        end
      end
    end

    context 'when the hook is in another organization' do
      let_it_be(:organization) { create(:organization) }
      let_it_be_with_reload(:hook) { create(:system_hook, organization: organization) }

      it_behaves_like 'a hook that gets automatically disabled on failure', filtered_by_scopes: false do
        let(:hook_factory) { :system_hook }
        let(:default_factory_arguments) { { organization: organization } }
        let(:log_organization_id) { organization.id }
      end

      describe '.executable/.disabled' do
        it 'does not filter hooks at the database level' do
          disabled_hook = create(:system_hook, organization: organization, recent_failures: 40)

          expect(described_class.executable).to include(hook, disabled_hook)
          expect(described_class.disabled).to be_empty
        end
      end
    end
  end

  context 'default attributes' do
    let(:system_hook) { described_class.new }

    it 'sets defined default parameters' do
      attrs = {
        push_events: false,
        repository_update_events: true,
        merge_requests_events: false
      }
      expect(system_hook).to have_attributes(attrs)
    end
  end

  describe 'validations' do
    describe 'url' do
      let(:url) { 'http://localhost:9000' }

      it { is_expected.to validate_presence_of(:organization_id) }

      context 'with a local URL' do
        using RSpec::Parameterized::TableSyntax

        let(:hook) { build(:system_hook, organization: organization, url: url) }

        before do
          create(:application_setting)
          stub_application_setting(
            allow_local_requests_from_system_hooks: system_hooks_setting,
            allow_local_requests_from_web_hooks_and_services: web_hooks_setting
          )
        end

        where(:organization, :system_hooks_setting, :web_hooks_setting, :allowed) do
          ref(:default_organization) | true  | false | true
          ref(:default_organization) | false | true  | false
          ref(:other_organization)   | true  | false | false
          ref(:other_organization)   | false | true  | true
          nil                        | true  | false | false
          nil                        | false | true  | true
        end

        with_them do
          it 'follows the setting for the organization on save and on delivery', :aggregate_failures do
            hook.validate

            expect(hook.errors[:url].empty?).to be(allowed)
            expect(hook.allow_local_requests?).to be(allowed)
          end
        end

        context 'with URL variables in another organization' do
          let(:hook) do
            build(:system_hook, organization: other_organization, url: 'http://{host}:9000',
              url_variables: { 'host' => 'localhost' })
          end

          where(:system_hooks_setting, :web_hooks_setting, :allowed) do
            true  | false | false
            false | true  | true
          end

          with_them do
            it 'validates the interpolated URL against the webhooks setting' do
              expect(hook.valid?).to be(allowed)
            end
          end
        end
      end
    end

    describe 'organization hooks limit' do
      let_it_be_with_reload(:plan_limits) { create(:plan_limits, :default_plan, organization_hooks: 1) }
      let_it_be(:organization) { create(:organization) }

      subject(:hook) { build(:system_hook, organization: organization) }

      it { is_expected.to be_valid }

      context 'when another organization is at the limit' do
        before do
          create(:system_hook, organization: create(:organization))
        end

        it { is_expected.to be_valid }
      end

      context 'when the organization has a service hook' do
        before do
          create(:service_hook, organization_id: organization.id)
        end

        it { is_expected.to be_valid }
      end

      context 'when the organization is at the limit' do
        let_it_be_with_reload(:existing_hook) { create(:system_hook, organization: organization) }

        it 'is invalid' do
          expect(hook).not_to be_valid
          expect(hook.errors[:base]).to contain_exactly('Maximum number of organization hooks (1) exceeded')
        end

        it 'allows updating an existing hook' do
          existing_hook.push_events = true

          expect(existing_hook).to be_valid
        end

        context 'when the limit is 0' do
          before do
            plan_limits.update!(organization_hooks: 0)
          end

          it { is_expected.to be_valid }
        end
      end

      context 'when the hook is in the default organization' do
        let_it_be(:default_organization) { create(:organization, :default) } # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- default organization hooks are not capped

        subject(:hook) { build(:system_hook, organization: default_organization) }

        before do
          create(:system_hook, organization: default_organization)
        end

        it { is_expected.to be_valid }
      end
    end
  end

  describe '#default_organization?' do
    using RSpec::Parameterized::TableSyntax

    where(:organization_id, :expected) do
      Organizations::Organization::DEFAULT_ORGANIZATION_ID | true # rubocop:disable Gitlab/AvoidConstDefaultOrganizationId -- the predicate compares against this id
      non_existing_record_id                               | false
      nil                                                  | false
    end

    with_them do
      it { expect(described_class.new(organization_id: organization_id).default_organization?).to be(expected) }
    end
  end

  describe 'associations' do
    it { is_expected.to have_many(:web_hook_logs) }
    it { is_expected.to belong_to :organization }
  end

  describe '.for_organization' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:other_organization) { create(:organization) }
    let_it_be(:hook) { create(:system_hook, organization: organization) }
    let_it_be(:other_hook) { create(:system_hook, organization: other_organization) }

    it 'returns only hooks of the given organization' do
      expect(described_class.for_organization(organization)).to contain_exactly(hook)
      expect(described_class.for_organization(other_organization)).to contain_exactly(other_hook)
    end

    it 'accepts an organization id' do
      expect(described_class.for_organization(organization.id)).to contain_exactly(hook)
    end

    it 'returns no hooks when the organization is nil' do
      expect(described_class.for_organization(nil)).to be_empty
    end
  end

  describe '#reload' do
    let_it_be(:organization) { create(:organization) }
    let_it_be_with_reload(:hook) { create(:system_hook, organization: organization) }

    it 'scopes the query to the organization of the hook' do
      expect { hook.reload }.not_to query_system_hooks_without_organization_id
      expect { hook.reset }.not_to query_system_hooks_without_organization_id
      expect { hook.reload(lock: true) }.not_to query_system_hooks_without_organization_id
    end

    it 'refreshes the attributes in place' do
      described_class.id_in(hook.id).update_all(recent_failures: 5)

      expect(hook.reset).to equal(hook)
      expect(hook.recent_failures).to eq(5)
    end
  end

  describe '#destroy' do
    it 'does not cascade to web_hook_logs' do
      web_hook = create(:system_hook)
      create_list(:web_hook_log, 3, web_hook: web_hook)

      expect { web_hook.destroy! }.not_to change { web_hook.web_hook_logs.count }
    end
  end

  describe "execute", :sidekiq_might_not_need_inline do
    let_it_be(:system_hook) { create(:system_hook) }
    let_it_be(:user) { create(:user) }
    let(:project) { build(:project, namespace: user.namespace) }
    let(:group) { build(:group) }
    let(:params) do
      { name: 'John Doe', username: 'jduser', email: 'jg@example.com', password: User.random_password,
        organization_id: group.organization_id }
    end

    before do
      WebMock.stub_request(:post, system_hook.url)
    end

    it "project_create hook" do
      Projects::CreateService.new(user, name: 'empty').execute
      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /project_create/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end

    it "project_destroy hook" do
      project.save!

      Projects::DestroyService.new(project, user, {}).async_execute

      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /project_destroy/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end

    it "user_create hook" do
      Users::CreateService.new(nil, params).execute

      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /user_create/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end

    it "user_destroy hook" do
      user.destroy!

      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /user_destroy/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end

    it "project member create hook" do
      project.add_maintainer(user)

      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /user_add_to_team/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end

    it "project member destroy hook" do
      project.add_maintainer(user)
      project.project_members.destroy_all # rubocop: disable Cop/DestroyAll

      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /user_remove_from_team/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end

    it "project member update hook" do
      project.save!
      project.add_guest(user)

      project.add_maintainer(user)

      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /user_update_for_team/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end

    %i[project group].each do |parent|
      it "#{parent} member access request hook" do
        create(:"#{parent}_member", requested_at: Time.current.utc)

        expect(WebMock).to have_requested(:post, system_hook.url).with(
          body: /user_access_request_to_#{parent}/,
          headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
        ).once
      end

      it "#{parent} member access request revoked hook" do
        member = create(:"#{parent}_member", requested_at: Time.current.utc)
        member.destroy!

        expect(WebMock).to have_requested(:post, system_hook.url).with(
          body: /user_access_request_revoked_for_#{parent}/,
          headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
        ).once
      end
    end

    it 'group create hook' do
      create(:group)

      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /group_create/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end

    it 'group destroy hook' do
      create(:group).destroy!

      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /group_destroy/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end

    it 'group member create hook' do
      group.add_maintainer(user)

      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /user_add_to_group/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end

    it 'group member destroy hook' do
      group.add_maintainer(user)
      group.group_members.destroy_all # rubocop: disable Cop/DestroyAll

      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /user_remove_from_group/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end

    it 'group member update hook' do
      group = create(:group)
      group.add_guest(user)
      group.add_maintainer(user)

      expect(WebMock).to have_requested(:post, system_hook.url).with(
        body: /user_update_for_group/,
        headers: { 'Content-Type' => 'application/json', 'X-Gitlab-Event' => 'System Hook' }
      ).once
    end
  end

  describe '.repository_update_hooks' do
    it 'returns hooks for repository update events only' do
      hook = create(:system_hook, repository_update_events: true)
      create(:system_hook, repository_update_events: false)
      expect(described_class.repository_update_hooks).to eq([hook])
    end
  end

  describe 'execute WebHookService' do
    let(:hook) { build(:system_hook) }
    let(:data) { { key: 'value' } }
    let(:hook_name) { 'system_hook' }

    it '#execute' do
      expect(WebHookService).to receive(:new).with(hook, data, hook_name, idempotency_key: anything,
        force: false).and_call_original

      expect_any_instance_of(WebHookService).to receive(:execute)

      hook.execute(data, hook_name)
    end

    it '#async_execute' do
      expect(WebHookService).to receive(:new).with(hook, data, hook_name, idempotency_key: anything).and_call_original

      expect_any_instance_of(WebHookService).to receive(:async_execute)

      hook.async_execute(data, hook_name)
    end
  end

  describe '#application_context' do
    let_it_be(:organization) { create(:organization) }
    let(:hook) { build(:system_hook, organization: organization) }

    it 'includes the type and organization' do
      expect(hook.application_context).to eq(
        related_class: 'SystemHook',
        organization: organization
      )
    end
  end

  describe '#pluralized_name' do
    subject { build(:system_hook).pluralized_name }

    it { is_expected.to eq('System hooks') }
  end

  describe '#help_path' do
    subject { build(:system_hook).help_path }

    it { is_expected.to eq('/help/administration/system_hooks.md') }
  end
end
