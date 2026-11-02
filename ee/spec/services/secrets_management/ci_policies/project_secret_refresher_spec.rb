# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::CiPolicies::ProjectSecretRefresher, :gitlab_secrets_manager, feature_category: :secrets_management do
  let_it_be_with_reload(:project) { create(:project) }
  let_it_be(:user) { create(:user) }

  let(:secrets_manager) { create(:project_secrets_manager, project: project) }
  let(:full_namespace_path) { secrets_manager.full_project_namespace_path }
  let(:ci_client) { secrets_manager_client.with_namespace(full_namespace_path) }
  let(:refresher) { described_class.new(secrets_manager, ci_client) }

  let(:secret_name) { 'TEST_SECRET' }
  let(:branch) { 'main' }
  let(:old_environment) { 'prod' }
  let(:new_environment) { 'staging' }
  let(:old_policy_name) { secrets_manager.ci_policy_name(old_environment, branch) }
  let(:new_policy_name) { secrets_manager.ci_policy_name(new_environment, branch) }

  before_all do
    project.add_owner(user)
  end

  before do
    provision_project_secrets_manager(secrets_manager, user)

    create_project_secret(
      user: user, project: project, name: secret_name, value: 'secret-value',
      environment: old_environment, branch: branch
    )
  end

  describe '#refresh_ci_policies_for', :aggregate_failures do
    # Callers write to OpenBao before they refresh policies. These examples skip that write,
    # to test that the refresher does not count the secret that it refreshes.
    context 'when the moved secret still has its old metadata in OpenBao' do
      let(:secret) do
        SecretsManagement::ProjectSecret.new(
          name: secret_name, project: project, environment: old_environment, branch: branch
        ).tap { |moved_secret| moved_secret.environment = new_environment }
      end

      it 'deletes the old policy and adds the secret to the new policy' do
        refresher.refresh_ci_policies_for(secret)

        expect_policy_not_to_exist(full_namespace_path, old_policy_name)
        expect(ci_client.get_policy(new_policy_name).paths).to include(secrets_manager.ci_full_path(secret_name))
      end

      context 'when another secret still uses the old policy' do
        let(:other_secret_name) { 'OTHER_SECRET' }

        before do
          create_project_secret(
            user: user, project: project, name: other_secret_name, value: 'other-value',
            environment: old_environment, branch: branch
          )
        end

        it 'keeps the old policy for the other secret' do
          refresher.refresh_ci_policies_for(secret)

          old_policy = ci_client.get_policy(old_policy_name)
          expect(old_policy.paths).to include(secrets_manager.ci_full_path(other_secret_name))
          expect(old_policy.paths).not_to include(secrets_manager.ci_full_path(secret_name))
          expect(old_policy.paths).not_to include(secrets_manager.ci_metadata_full_path(secret_name))
        end
      end
    end

    context 'when deleting a secret that still exists in OpenBao' do
      let(:secret) do
        SecretsManagement::ProjectSecret.new(
          name: secret_name, project: project, environment: old_environment, branch: branch
        )
      end

      it 'deletes the policy' do
        refresher.refresh_ci_policies_for(secret, delete_operation: true)

        expect_policy_not_to_exist(full_namespace_path, old_policy_name)
      end
    end
  end
end
