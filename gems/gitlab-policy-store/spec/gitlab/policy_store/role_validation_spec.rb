# frozen_string_literal: true

require "spec_helper"

RSpec.describe Gitlab::PolicyStore::RoleValidation do
  # Subclasses the port rather than including the module directly, so dropping the
  # include from Ports::PolicyRepository fails here instead of passing silently.
  # Adapter-level coverage lives in the EE repository spec; the gem has no adapter.
  let(:validator) do
    Class.new(Gitlab::PolicyStore::Ports::PolicyRepository) { public :validate_action_roles! }.new
  end

  subject(:validate) do
    validator.validate_action_roles!(trigger_type: trigger_type, actions: actions)
  end

  context 'with a deployment trigger' do
    let(:trigger_type) { 'deployment_requested' }

    context 'with CD roles' do
      let(:actions) do
        [{ 'type' => 'require_approval', 'value' => { 'roles' => %w[release_manager deployment_observer] } }]
      end

      it { expect { validate }.not_to raise_error }
    end

    context 'with GitLab roles' do
      let(:actions) do
        [{ 'type' => 'require_approval', 'value' => { 'roles' => %w[developer maintainer] } }]
      end

      it 'rejects them' do
        expect { validate }.to raise_error(
          Gitlab::PolicyStore::ValidationError, /GitLab roles.*cannot be used with deployment triggers/
        )
      end
    end

    context 'with GitLab and CD roles mixed' do
      let(:actions) do
        [{ 'type' => 'require_approval', 'value' => { 'roles' => %w[maintainer release_manager] } }]
      end

      it 'rejects the GitLab role' do
        expect { validate }.to raise_error(
          Gitlab::PolicyStore::ValidationError, /GitLab roles.*cannot be used with deployment triggers/
        )
      end
    end

    context 'with a role outside the vocabulary' do
      let(:actions) do
        [{ 'type' => 'require_approval', 'value' => { 'roles' => ['unknown_role'] } }]
      end

      it 'rejects it' do
        expect { validate }.to raise_error(Gitlab::PolicyStore::ValidationError, /invalid roles: unknown_role/)
      end
    end

    context 'with an action that carries no roles' do
      let(:actions) { [{ 'type' => 'require_approval', 'value' => {} }] }

      it { expect { validate }.not_to raise_error }
    end

    context 'with an action that takes no roles at all' do
      let(:actions) { [{ 'type' => 'block', 'value' => { 'message' => 'Blocked' } }] }

      it { expect { validate }.not_to raise_error }
    end
  end

  context 'with a non-deployment trigger' do
    let(:trigger_type) { Gitlab::PolicyStore::Triggers::PROJECT_CREATED }

    context 'with GitLab roles' do
      let(:actions) do
        [{ 'type' => 'require_approval', 'value' => { 'roles' => %w[developer maintainer] } }]
      end

      it { expect { validate }.not_to raise_error }
    end

    context 'with CD roles' do
      let(:actions) do
        [{ 'type' => 'require_approval', 'value' => { 'roles' => %w[release_manager deployment_observer] } }]
      end

      it 'rejects them' do
        expect { validate }.to raise_error(
          Gitlab::PolicyStore::ValidationError, /CD roles.*can only be used with deployment triggers/
        )
      end
    end
  end
end
