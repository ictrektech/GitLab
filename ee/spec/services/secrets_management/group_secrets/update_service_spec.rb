# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleMemoizedHelpers -- we need to test a lot of partial attribute changes
RSpec.describe SecretsManagement::GroupSecrets::UpdateService, :gitlab_secrets_manager, feature_category: :secrets_management do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:user) { create(:user) }

  let(:secrets_manager) { create(:group_secrets_manager, group: group) }
  let(:full_namespace_path) { secrets_manager.full_group_namespace_path }
  let(:service) { described_class.new(group, user) }
  let(:new_description) { 'updated description' }
  let(:new_value) { 'new-secret-value' }
  let(:new_environment) { 'staging' }
  let(:new_protected) { false }
  let(:new_rotation_interval_days) { 30 }

  let(:original_name) { 'TEST_SECRET' }
  let(:original_description) { 'original description' }
  let(:original_value) { 'original-value' }
  let(:original_environment) { 'production' }
  let(:original_protected) { true }
  let(:original_rotation_interval_days) { nil }

  let(:name) { original_name }
  let(:description) { nil }
  let(:value) { nil }
  let(:environment) { nil }
  let(:protected) { nil }
  let(:rotation_interval_days) { nil }
  let(:initial_metadata_version) { 2 }
  let(:metadata_cas) { initial_metadata_version }
  let(:version_on_create) { 1 }

  let(:execute_params) do
    {
      name: name,
      metadata_cas: metadata_cas,
      description: description,
      value: value,
      environment: environment,
      protected: protected,
      rotation_interval_days: rotation_interval_days
    }
  end

  subject(:result) { service.execute(**execute_params) }

  before_all do
    group.add_owner(user)
  end

  def provision_secrets_manager(secrets_manager, user)
    provision_group_secrets_manager(secrets_manager, user)
  end

  def rotation_info_for_secret(resource, name, version = 1)
    secret_rotation_info_for_group_secret(resource, name, version)
  end

  def create_initial_secret
    SecretsManagement::GroupSecrets::CreateService.new(group, user).execute(
      name: original_name,
      description: original_description,
      value: original_value,
      environment: original_environment,
      protected: original_protected,
      rotation_interval_days: original_rotation_interval_days
    )
  end

  it_behaves_like 'a service for updating a secret', 'group'

  describe '#execute', :aggregate_failures, :freeze_time do
    let(:ci_client) { secrets_manager_client.with_namespace(full_namespace_path) }
    let(:secret_path) { secrets_manager.ci_full_path(name) }
    let(:original_policy_name) { policy_name_for(original_environment, original_protected) }

    def policy_name_for(environment, protected)
      secrets_manager.ci_policy_name_for_environment(environment, protected: protected)
    end

    before do
      provision_secrets_manager(secrets_manager, user)
      create_initial_secret
    end

    context 'when the secret is not valid for update' do
      it 'returns an error without updating' do
        allow_next_instance_of(SecretsManagement::GroupSecret) do |secret|
          allow(secret).to receive(:valid_for_update?).and_return(false)
          secret.errors.add(:base, 'Secret create in progress.')
        end

        expect(result).not_to be_success
        expect(result.message).to eq('Secret create in progress.')
      end
    end

    context 'when updating all attributes' do
      let(:description) { new_description }
      let(:value) { new_value }
      let(:environment) { new_environment }
      let(:protected) { new_protected }

      it 'updates the group secret with correct attributes' do
        expect(result).to be_success
        secret = result.payload[:secret]
        expect(secret.group).to eq(group)
        expect(secret.description).to eq(new_description)
        expect(secret.environment).to eq(new_environment)
        expect(secret.protected).to be false

        expect_kv_secret_to_have_value(
          group.secrets_manager.full_group_namespace_path,
          group.secrets_manager.ci_secrets_mount_path,
          secrets_manager.ci_data_path(name),
          new_value
        )

        expect_kv_secret_to_have_custom_metadata(
          group.secrets_manager.full_group_namespace_path,
          group.secrets_manager.ci_secrets_mount_path,
          secrets_manager.ci_data_path(name),
          "description" => new_description,
          "environment" => new_environment,
          "protected" => "false"
        )
      end

      it 'transitions to the correct policy' do
        expect(result).to be_success

        client = secrets_manager_client.with_namespace(secrets_manager.full_group_namespace_path)

        # Validate new policy has path
        new_policy_name = group.secrets_manager.ci_policy_name_for_environment(new_environment,
          protected: new_protected)
        new_policy = client.get_policy(new_policy_name)
        expect(new_policy).not_to be_nil
        expect(new_policy.paths).to include(group.secrets_manager.ci_full_path(name))

        # Validate old policy no longer has path (policy may be deleted or empty)
        old_policy_name = group.secrets_manager.ci_policy_name_for_environment(original_environment,
          protected: original_protected)
        old_policy = client.get_policy(old_policy_name)
        expect(old_policy.paths).to be_empty
      end
    end

    context 'with partial updates' do
      context 'when updating description only' do
        let(:description) { new_description }

        it 'updates only the description' do
          expect(result).to be_success
          secret = result.payload[:secret]
          expect(secret.description).to eq(new_description)
          expect(secret.environment).to eq(original_environment) # unchanged
          expect(secret.protected).to eq(original_protected) # unchanged
        end
      end

      context 'when updating environment only' do
        let(:environment) { new_environment }

        it 'updates only the environment' do
          expect(result).to be_success
          secret = result.payload[:secret]
          expect(secret.description).to eq(original_description) # unchanged
          expect(secret.environment).to eq(new_environment)
          expect(secret.protected).to eq(original_protected) # unchanged

          expect_kv_secret_to_have_custom_metadata(
            group.secrets_manager.full_group_namespace_path,
            group.secrets_manager.ci_secrets_mount_path,
            secrets_manager.ci_data_path(name),
            "environment" => new_environment
          )
        end
      end

      context 'when updating protected only' do
        let(:protected) { new_protected }

        it 'updates only the protected flag' do
          expect(result).to be_success
          secret = result.payload[:secret]
          expect(secret.description).to eq(original_description) # unchanged
          expect(secret.environment).to eq(original_environment) # unchanged
          expect(secret.protected).to eq(new_protected)

          expect_kv_secret_to_have_custom_metadata(
            group.secrets_manager.full_group_namespace_path,
            group.secrets_manager.ci_secrets_mount_path,
            secrets_manager.ci_data_path(name),
            "protected" => new_protected.to_s
          )
        end
      end

      context 'when updating value only' do
        let(:value) { new_value }

        it 'updates only the value' do
          expect(result).to be_success

          expect_kv_secret_to_have_value(
            group.secrets_manager.full_group_namespace_path,
            group.secrets_manager.ci_secrets_mount_path,
            secrets_manager.ci_data_path(name),
            new_value
          )

          # Verify metadata is unchanged
          expect_kv_secret_to_have_custom_metadata(
            group.secrets_manager.full_group_namespace_path,
            group.secrets_manager.ci_secrets_mount_path,
            secrets_manager.ci_data_path(name),
            "description" => original_description,
            "environment" => original_environment,
            "protected" => original_protected.to_s
          )
        end
      end
    end

    context 'when changing environment triggers policy transition' do
      let(:environment) { 'staging' }
      let(:protected) { original_protected } # Keep protected same

      it 'moves secret to new policy' do
        expect(result).to be_success

        client = secrets_manager_client.with_namespace(secrets_manager.full_group_namespace_path)

        # New policy should have the secret
        new_policy_name = group.secrets_manager.ci_policy_name_for_environment('staging', protected: original_protected)
        new_policy = client.get_policy(new_policy_name)
        expect(new_policy.paths).to include(group.secrets_manager.ci_full_path(name))

        # Old policy should be deleted or empty
        old_policy_name = group.secrets_manager.ci_policy_name_for_environment(original_environment,
          protected: original_protected)
        old_policy = client.get_policy(old_policy_name)
        expect(old_policy.paths).to be_empty
      end

      it 'deletes the old policy when no other secret uses it' do
        expect(result).to be_success

        expect_policy_not_to_exist(full_namespace_path, original_policy_name)
      end

      context 'when another secret uses the old policy' do
        let(:other_secret_name) { 'OTHER_SECRET' }

        before do
          SecretsManagement::GroupSecrets::CreateService.new(group, user).execute(
            name: other_secret_name,
            value: 'other-value',
            environment: original_environment,
            protected: original_protected
          )
        end

        it 'keeps the old policy for the other secret' do
          expect(result).to be_success

          old_policy = ci_client.get_policy(original_policy_name)
          expect(old_policy.paths).to include(secrets_manager.ci_full_path(other_secret_name))
          expect(old_policy.paths).not_to include(secret_path)
        end
      end

      context 'when another secret already uses the new policy' do
        let(:other_secret_name) { 'OTHER_SECRET' }

        before do
          SecretsManagement::GroupSecrets::CreateService.new(group, user).execute(
            name: other_secret_name,
            value: 'other-value',
            environment: environment,
            protected: original_protected
          )
        end

        it 'adds the secret next to the other secret' do
          expect(result).to be_success

          new_policy = ci_client.get_policy(policy_name_for(environment, original_protected))
          expect(new_policy.paths).to include(secret_path, secrets_manager.ci_full_path(other_secret_name))
        end
      end
    end

    context 'when the user only has read permission' do
      let_it_be(:reporter) { create(:user, reporter_of: group) }

      let(:service) { described_class.new(group, reporter) }

      before do
        update_group_secrets_permission(
          user: user, group: group, actions: %w[read], principal: { id: reporter.id, type: 'User' }
        )
      end

      shared_examples 'a denied update that keeps CI access unchanged' do
        it 'does not move the secret to another CI policy' do
          expect { result }.to raise_error(
            SecretsManagement::SecretsManagerClient::ApiError,
            "1 error occurred:\n\t* permission denied\n\n"
          )

          expect(ci_client.get_policy(original_policy_name).paths).to include(secret_path)
          expect(ci_client.get_policy(target_policy_name).paths).not_to include(secret_path)

          expect_kv_secret_to_have_custom_metadata(
            full_namespace_path,
            secrets_manager.ci_secrets_mount_path,
            secrets_manager.ci_data_path(name),
            "environment" => original_environment,
            "protected" => original_protected.to_s
          )
        end
      end

      context 'when changing the environment' do
        let(:environment) { new_environment }
        let(:target_policy_name) { policy_name_for(new_environment, original_protected) }

        it_behaves_like 'a denied update that keeps CI access unchanged'
      end

      context 'when changing the protected flag' do
        let(:protected) { new_protected }
        let(:target_policy_name) { policy_name_for(original_environment, new_protected) }

        it_behaves_like 'a denied update that keeps CI access unchanged'
      end
    end

    context 'when the user can update secrets but not read their metadata' do
      let_it_be(:reporter) { create(:user, reporter_of: group) }

      let(:service) { described_class.new(group, reporter) }
      let(:actions) { %w[write read_value] }
      let(:value) { new_value }

      before do
        update_group_secrets_permission(
          user: user, group: group, actions: actions, principal: { id: reporter.id, type: 'User' }
        )
      end

      it 'updates the secret' do
        expect(result).to be_success
        expect_kv_secret_to_have_value(
          full_namespace_path, secrets_manager.ci_secrets_mount_path, secrets_manager.ci_data_path(name), new_value
        )
      end

      context 'when the grant has no update' do
        let(:actions) { %w[create read_value] }

        it 'raises the permission error' do
          expect { result }.to raise_error(SecretsManagement::SecretsManagerClient::ApiError, /permission denied/)
        end
      end
    end

    context 'when the CI policy refresh fails after the metadata write' do
      let(:environment) { new_environment }

      before do
        allow_next_instance_of(SecretsManagement::CiPolicies::GroupSecretRefresher) do |refresher|
          allow(refresher).to receive(:refresh_ci_policies_for)
            .and_raise(SecretsManagement::SecretsManagerClient::ApiError, 'policy write failed')
        end
      end

      it 'leaves the update incomplete without granting new CI access' do
        expect { result }.to raise_error(SecretsManagement::SecretsManagerClient::ApiError, 'policy write failed')

        expect(ci_client.get_policy(original_policy_name).paths).to include(secret_path)
        expect(ci_client.get_policy(policy_name_for(new_environment, original_protected)).paths)
          .not_to include(secret_path)

        expect_kv_secret_to_have_custom_metadata(
          full_namespace_path,
          secrets_manager.ci_secrets_mount_path,
          secrets_manager.ci_data_path(name),
          "environment" => new_environment
        )
        expect_kv_secret_not_to_have_custom_metadata(
          full_namespace_path,
          secrets_manager.ci_secrets_mount_path,
          secrets_manager.ci_data_path(name),
          "update_completed_at"
        )
      end
    end

    context 'when changing protected flag triggers policy transition' do
      let(:environment) { original_environment } # Keep environment same
      let(:protected) { new_protected }

      it 'moves secret to new policy' do
        expect(result).to be_success

        client = secrets_manager_client.with_namespace(secrets_manager.full_group_namespace_path)

        # New policy should have the secret
        new_policy_name = group.secrets_manager.ci_policy_name_for_environment(original_environment,
          protected: new_protected)
        new_policy = client.get_policy(new_policy_name)
        expect(new_policy.paths).to include(group.secrets_manager.ci_full_path(name))

        # Old policy should be deleted or empty
        old_policy_name = group.secrets_manager.ci_policy_name_for_environment(original_environment,
          protected: original_protected)
        old_policy = client.get_policy(old_policy_name)
        expect(old_policy.paths).to be_empty
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
