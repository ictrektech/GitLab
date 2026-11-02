# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SystemHooksService, feature_category: :webhooks do
  describe '#execute_hooks_for' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project) }
    let_it_be(:group_member) { create(:group_member, source: group, user: user) }
    let_it_be(:project_member) { create(:project_member, source: project, user: user) }
    let_it_be(:key) { create(:key, user: user) }
    let_it_be(:deploy_key) { create(:key) }

    let(:event) { :create }

    using RSpec::Parameterized::TableSyntax

    where(:model_name, :builder_class, :organization_source) do
      :group_member | Gitlab::HookData::GroupMemberBuilder | :source
      :group | Gitlab::HookData::GroupBuilder | :self
      :project_member | Gitlab::HookData::ProjectMemberBuilder | :source
      :user | Gitlab::HookData::UserBuilder | :self
      :project | Gitlab::HookData::ProjectBuilder | :self
      :key | Gitlab::HookData::KeyBuilder | :self
      :deploy_key | Gitlab::HookData::KeyBuilder | :self
    end

    with_them do
      it 'builds the data with the relevant builder class and then calls #execute_hooks with the obtained data' do
        data = double
        model = public_send(model_name)

        expect_next_instance_of(builder_class, model) do |builder|
          if builder_class == Gitlab::HookData::ProjectBuilder
            expect(builder).to receive(:build).with(event, include_deprecated_owner: true).and_return(data)
          else
            expect(builder).to receive(:build).with(event).and_return(data)
          end
        end

        service = described_class.new
        organization = organization_source == :source ? model.source.organization : model.organization

        expect_next_instance_of(SystemHooksService) do |system_hook_service|
          expect(system_hook_service).to receive(:execute_hooks).with(data, organization: organization)
        end

        service.execute_hooks_for(model, event)
      end
    end
  end

  describe '#execute_hooks_for with hooks in multiple organizations' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:user) { create(:user, organization: organization) }
    let_it_be(:group) { create(:group, organization: organization) }
    let_it_be(:project) { create(:project, group: group, organization: organization) }

    let_it_be_with_refind(:group_member) { create(:group_member, source: group, user: user) }
    let_it_be_with_refind(:project_member) do
      create(:project_member, source: project, user: create(:user, organization: organization))
    end

    let_it_be_with_refind(:key) { create(:key, user: user) }
    let_it_be_with_refind(:deploy_key) { create(:deploy_key, organization: organization) }

    where(model_name: %i[project group user group_member project_member key deploy_key])

    with_them do
      it_behaves_like 'system hook delivery scoped to the organization' do
        def execute_system_hooks
          described_class.new.execute_hooks_for(public_send(model_name), :create)
        end
      end
    end
  end

  describe 'user and key events go only to the owning organization' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:owning_organization) { create(:organization) }
    let_it_be(:other_organization) { create(:organization) }
    let_it_be(:user) { create(:user, organization: owning_organization) }
    let_it_be(:key) { create(:key, user: user) }
    let_it_be(:other_group) { create(:group, organization: other_organization) }
    let_it_be(:other_group_member) { create(:group_member, source: other_group, user: user) }
    let_it_be(:owning_organization_hook) { create(:system_hook, organization: owning_organization) }
    let_it_be(:other_organization_hook) { create(:system_hook, organization: other_organization) }

    before do
      allow(WebHookWorker).to receive(:perform_async)
    end

    where(:model_name, :event) do
      :user | :create
      :user | :rename
      :user | :destroy
      :user | :failed_login
      :key  | :create
      :key  | :destroy
    end

    with_them do
      it 'queues only the owning organization hook', :aggregate_failures do
        described_class.new.execute_hooks_for(public_send(model_name), event)

        expect(WebHookWorker).to have_received(:perform_async).with(owning_organization_hook.id, any_args).once
        expect(WebHookWorker).not_to have_received(:perform_async).with(other_organization_hook.id, any_args)
      end
    end

    context 'with a membership in a group of another organization' do
      it 'queues only the group organization hook with the webhook email', :aggregate_failures do
        described_class.new.execute_hooks_for(other_group_member, :create)

        expect(WebHookWorker).to have_received(:perform_async)
          .with(other_organization_hook.id, hash_including('user_email' => user.webhook_email), any_args).once
        expect(WebHookWorker).not_to have_received(:perform_async).with(owning_organization_hook.id, any_args)
        expect(user.webhook_email).not_to eq(user.email)
      end
    end
  end

  describe '#execute_hooks' do
    let(:data) { { key: :value } }
    let_it_be(:organization) { create(:organization) }

    subject { described_class.new.execute_hooks(data, organization: organization) }

    it 'executes system hooks with the given data' do
      hook = create(:system_hook, organization: organization)

      allow(SystemHook).to receive_message_chain(:for_organization, :executable, :hooks_for, :find_each).and_yield(hook)

      expect(hook).to receive(:async_execute).with(data, 'system_hooks')

      subject
    end

    it 'executes FileHook with the given data' do
      expect(Gitlab::FileHook).to receive(:execute_all_async).with(data)

      subject
    end

    it_behaves_like 'system hook delivery scoped to the organization' do
      def execute_system_hooks
        described_class.new.execute_hooks(data, organization: organization)
      end
    end

    context 'when a hook is disabled after repeated failures' do
      let(:disabled_attributes) do
        { recent_failures: WebHooks::AutoDisabling::PERMANENTLY_DISABLED_FAILURE_THRESHOLD + 1 }
      end

      before do
        allow(WebHookWorker).to receive(:perform_async)
      end

      it 'does not enqueue a hook of a non-default organization' do
        create(:system_hook, organization: organization, **disabled_attributes)

        subject

        expect(WebHookWorker).not_to have_received(:perform_async)
      end

      it 'still enqueues a hook of the default organization' do
        # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- default organization hooks belong to instance admins
        default_organization = create(:organization, :default)
        # rubocop:enable Gitlab/RSpec/AvoidCreateDefaultOrganization
        hook = create(:system_hook, organization: default_organization, **disabled_attributes)

        described_class.new.execute_hooks(data, organization: default_organization)

        expect(WebHookWorker).to have_received(:perform_async).with(hook.id, anything, 'system_hooks', anything)
      end
    end

    it 'requires an organization' do
      expect { described_class.new.execute_hooks(data) }.to raise_error(ArgumentError, /organization/)
    end

    context 'when the organization is nil' do
      subject { described_class.new.execute_hooks(data, organization: nil) }

      it 'does not execute any system hooks and logs a warning' do
        create(:system_hook, organization: organization)

        expect(Gitlab::AppLogger).to receive(:warn).with(
          a_hash_including(message: 'System hooks not executed: organization could not be resolved')
        )
        expect(WebHookWorker).not_to receive(:perform_async)

        subject
      end

      it 'still executes FileHook with the given data' do
        expect(Gitlab::FileHook).to receive(:execute_all_async).with(data)

        subject
      end
    end
  end
end
