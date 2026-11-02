# frozen_string_literal: true

require 'spec_helper'
require Rails.root.join('gems/gitlab-policy-store/spec/support/shared_examples/policy_repository_shared_examples')

# rubocop:disable Rails/SaveBang -- repository is the policy store port, not ActiveRecord; it has no create!
RSpec.describe Govern::PolicyStore::ActiveRecordPolicyRepository, feature_category: :security_policy_management do
  subject(:repository) { described_class.new }

  let_it_be(:group) { create(:group) }
  let_it_be(:other_organization) { create(:organization) }

  let(:organization_id) { group.organization_id }
  let(:broken_rule) do
    { 'type' => 'custom', 'value' => "package governance\n\nviolation contains {\"msg\": \"x\" if {" }
  end

  # The overrides belong in the block, not alongside it: a `let` inside the shared
  # example defines it on the nested group and would otherwise shadow ours.
  it_behaves_like 'a policy repository' do
    let(:namespace_id) { group.id }
    let(:other_organization_id) { other_organization.id }
    let(:trigger_type) { 'project.before_settings_update' }
    let(:other_trigger_type) { 'project.after_create' }
  end

  # Pins the ordering: the port must reject before ActiveRecord's own phrasing can win,
  # because callers surface these messages verbatim.
  describe 'validation messages' do
    let(:valid_attributes) do
      { organization_id: organization_id, name: 'Message policy', trigger_type: 'deployment_requested' }
    end

    def creation_message_from(attributes)
      repository.create(attributes)

      nil
    rescue ::Gitlab::PolicyStore::ValidationError => error
      error.message
    end

    def update_message_from(attributes)
      created = repository.create(valid_attributes)
      repository.update(created.id, attributes)

      nil
    rescue ::Gitlab::PolicyStore::ValidationError => error
      error.message
    end

    def self.length_message(attribute)
      limit = ::Gitlab::PolicyStore::Ports::PolicyRepository::TEXT_LIMITS[attribute]

      "#{attribute} exceeds maximum length of #{limit} characters"
    end

    def self.vocabulary_message(attribute, permitted)
      "#{attribute} must be one of: #{permitted.join(', ')} (got \"bogus\")"
    end

    {
      'a name over the length limit' => [
        { name: 'a' * 256 }, length_message(:name)
      ],
      'a description over the length limit' => [
        { description: 'a' * 4097 }, length_message(:description)
      ],
      'a name of only whitespace' => [
        { name: '   ' }, 'Missing required attributes: name'
      ],
      'a nulled trigger type' => [
        { trigger_type: nil }, 'Missing required attributes: trigger_type'
      ],
      'a nulled rules array' => [
        { rules: nil }, 'Attributes cannot be null: rules'
      ],
      'a mode outside the vocabulary' => [
        { mode: 'bogus' },
        vocabulary_message(:mode, ::Gitlab::PolicyStore::Ports::PolicyRepository::MODES)
      ],
      'a lifecycle_state outside the vocabulary' => [
        { lifecycle_state: 'bogus' },
        vocabulary_message(:lifecycle_state, ::Gitlab::PolicyStore::Ports::PolicyRepository::LIFECYCLE_STATES)
      ],
      'a trigger_type outside the vocabulary' => [
        { trigger_type: 'bogus' },
        vocabulary_message(:trigger_type, ::Gitlab::PolicyStore::Triggers::TYPES)
      ]
    }.each do |rejected_case, (invalid_attribute, expected_message)|
      it "rejects #{rejected_case} on create with the port's message" do
        expect(creation_message_from(valid_attributes.merge(invalid_attribute))).to eq(expected_message)
      end

      it "rejects #{rejected_case} on update with the port's message" do
        expect(update_message_from(invalid_attribute)).to eq(expected_message)
      end
    end

    it 'lists every missing required attribute at once' do
      expect(creation_message_from({})).to eq('Missing required attributes: organization_id, name, trigger_type')
    end
  end

  describe '#create' do
    let(:create_attributes) do
      { organization_id: organization_id, namespace_id: group.id, name: 'Adapter policy',
        trigger_type: 'project.before_settings_update' }
    end

    it 'rejects an over-limit name before the scope reaches the transpiler' do
      expect(Gitlab::PolicyStore::ScopeTranspiler).not_to receive(:new)

      over_limit = create_attributes.merge(
        name: 'n' * (Gitlab::PolicyStore::Ports::PolicyRepository::TEXT_LIMITS[:name] + 1),
        policy_scope: { 'projects' => { 'including' => [{ 'id' => 1 }] } }
      )

      expect { repository.create(over_limit) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /name exceeds maximum length/)
    end

    it 'raises ValidationError when the organization does not own the namespace' do
      expect { repository.create(create_attributes.merge(organization_id: other_organization.id)) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /must match the owning namespace's organization/)
    end

    it 'raises ValidationError when validations fail' do
      repository.create(create_attributes)

      expect { repository.create(create_attributes) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /Name has already been taken/)
    end

    it 'raises ValidationError for unknown enum values' do
      expect { repository.create(create_attributes.merge(trigger_type: 'bogus')) }
        .to raise_error(Gitlab::PolicyStore::ValidationError,
          /trigger_type must be one of: deployment_requested, environment_advanced, deployment_promoted.*bogus/)
    end

    it 'raises ValidationError for an approval role outside the vocabulary' do
      action = { 'type' => 'require_approval', 'value' => { 'roles' => %w[bogus] } }

      expect { repository.create(create_attributes.merge(actions: [action])) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, 'action 0: invalid roles: bogus')
    end

    it 'raises ValidationError for a GitLab role on a deployment trigger' do
      action = { 'type' => 'require_approval', 'value' => { 'roles' => %w[developer] } }

      organization_wide_deployment = create_attributes.merge(namespace_id: nil, trigger_type: 'deployment_requested')

      expect { repository.create(organization_wide_deployment.merge(actions: [action])) }
        .to raise_error(Gitlab::PolicyStore::ValidationError,
          'action 0: GitLab roles (developer) cannot be used with deployment triggers, use CD roles instead')
    end

    it 'returns copies of structured data, not references into the record' do
      policy = repository.create(create_attributes.merge(actions: [{ 'type' => 'require_approval' }]))
      policy.actions.first['injected'] = true

      expect(repository.find(policy.id).actions.first).not_to have_key('injected')
    end

    it 'persists scope_dimensions in the jsonb column, recoverable across a fresh find' do
      created = repository.create(create_attributes.merge(policy_scope: { compliance_frameworks: [{ id: 5 }] }))

      expect(repository.find(created.id).scope_dimensions).to eq(['compliance_frameworks'])
    end

    it 'translates the duplicate-name race the unique index loses to' do
      repository.create(create_attributes)
      allow_next_instance_of(Govern::Policy) do |policy|
        allow(policy).to receive(:valid?).and_return(true)
      end

      expect { repository.create(create_attributes) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, 'Name has already been taken')
    end

    context 'when the database raises RecordNotUnique for the name constraint' do
      let(:constraint_error) do
        ActiveRecord::RecordNotUnique.new(
          'PG::UniqueViolation: ERROR: duplicate key value violates unique constraint ' \
            '"unique_govern_policies_org_namespace_and_name"'
        )
      end

      it 'translates the constraint violation to a friendly validation error' do
        allow_next_instance_of(Govern::Policy) do |policy|
          allow(policy).to receive(:save).and_raise(constraint_error)
        end

        expect { repository.create(create_attributes) }
          .to raise_error(Gitlab::PolicyStore::ValidationError, 'Name has already been taken')
      end
    end

    context 'when the database raises RecordNotUnique for the legacy name constraint' do
      let(:legacy_constraint_error) do
        ActiveRecord::RecordNotUnique.new(
          'PG::UniqueViolation: ERROR: duplicate key value violates unique constraint ' \
            '"unique_govern_policies_organization_id_and_name"'
        )
      end

      it 'translates the legacy constraint violation to a friendly validation error' do
        allow_next_instance_of(Govern::Policy) do |policy|
          allow(policy).to receive(:save).and_raise(legacy_constraint_error)
        end

        expect { repository.create(create_attributes) }
          .to raise_error(Gitlab::PolicyStore::ValidationError, 'Name has already been taken')
      end
    end

    context 'when the database raises RecordNotUnique for an unrelated constraint' do
      let(:other_constraint_error) do
        ActiveRecord::RecordNotUnique.new(
          'PG::UniqueViolation: ERROR: duplicate key value violates unique constraint ' \
            '"some_other_constraint"'
        )
      end

      it 're-raises the original exception' do
        allow_next_instance_of(Govern::Policy) do |policy|
          allow(policy).to receive(:save).and_raise(other_constraint_error)
        end

        expect { repository.create(create_attributes) }
          .to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    it 'inserts no row when a rule does not parse', :aggregate_failures do
      expect { repository.create(create_attributes.merge(rules: [broken_rule])) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /\Arules\[0\] is invalid/)

      expect(Govern::Policy.where(name: 'Adapter policy')).to be_empty
    end

    it 'raises EngineError when the merged module does not parse', :aggregate_failures do
      allow_next_instance_of(Gitlab::PolicyStore::RuleProgramMerger) do |merger|
        allow(merger).to receive(:merge).and_return("package governance\n\nviolation contains {\n")
      end
      rules = [{ 'type' => 'environment', 'value' => { 'tiers' => ['production'] } }]

      expect { repository.create(create_attributes.merge(rules: rules)) }
        .to raise_error(Gitlab::PolicyStore::EngineError, /\Apolicy_merged_program is invalid/)

      expect(Govern::Policy.where(name: 'Adapter policy')).to be_empty
    end
  end

  describe '#list' do
    it 'clamps an oversized offset before it reaches the query, rather than scanning past it' do
      requested_offset = described_class::MAX_OFFSET + 12_345

      recorder = ActiveRecord::QueryRecorder.new do
        repository.list(organization_id: organization_id, offset: requested_offset)
      end

      expect(recorder.log.join).to include("OFFSET #{described_class::MAX_OFFSET} ")
      expect(recorder.log.join).not_to include("OFFSET #{requested_offset} ")
    end
  end

  describe '#update' do
    let(:policy) do
      repository.create(organization_id: organization_id, namespace_id: group.id,
        name: 'Update policy', trigger_type: 'project.before_settings_update')
    end

    it 'rejects an over-limit name before the scope reaches the transpiler' do
      scoped = repository.create(organization_id: organization_id, name: 'Renameable',
        trigger_type: 'deployment_requested',
        policy_scope: { 'projects' => { 'including' => [{ 'id' => 1 }] } })

      expect(Gitlab::PolicyStore::ScopeTranspiler).not_to receive(:new)

      over_limit_name = 'n' * (Gitlab::PolicyStore::Ports::PolicyRepository::TEXT_LIMITS[:name] + 1)

      expect { repository.update(scoped.id, name: over_limit_name) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /name exceeds maximum length/)
    end

    it 'raises ValidationError for unknown enum values' do
      expect { repository.update(policy.id, { mode: 'bogus' }) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /mode must be one of: audit, warn, enforce.*bogus/)
    end

    it 'raises ValidationError for an approval role outside the vocabulary' do
      action = { 'type' => 'require_approval', 'value' => { 'roles' => %w[bogus] } }

      expect { repository.update(policy.id, { actions: [action] }) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, 'action 0: invalid roles: bogus')
    end

    # Rows carrying roles their trigger disallows predate the check, and must stay editable.
    context 'with a stored GitLab role on a deployment trigger' do
      let(:stored_policy) do
        create(:govern_policy, :without_namespace, organization: group.organization,
          trigger_type: :deployment_requested,
          actions: [{ 'type' => 'require_approval', 'value' => { 'roles' => %w[developer] } }])
      end

      it 'leaves an edit that touches neither actions nor the trigger alone' do
        expect(repository.update(stored_policy.id, { name: 'Renamed policy' }).name).to eq('Renamed policy')
      end

      it 'raises ValidationError when the trigger moves to another deployment trigger' do
        expect { repository.update(stored_policy.id, { trigger_type: 'deployment_promoted' }) }
          .to raise_error(Gitlab::PolicyStore::ValidationError,
            'action 0: GitLab roles (developer) cannot be used with deployment triggers, use CD roles instead')
      end

      it 'accepts the trigger moving off deployment triggers, which makes the stored role allowed',
        :aggregate_failures do
        updated = repository.update(stored_policy.id, { trigger_type: 'project.before_settings_update' })

        expect(updated.trigger_type).to eq('project.before_settings_update')
        expect(updated.actions).to eq(stored_policy.actions)
      end
    end

    # The mirror case: the stored combination is legal, and stays legal only while the trigger does.
    context 'with a stored CD role on a deployment trigger' do
      let(:stored_policy) do
        create(:govern_policy, :without_namespace, organization: group.organization,
          trigger_type: :deployment_requested,
          actions: [{ 'type' => 'require_approval', 'value' => { 'roles' => %w[release_manager] } }])
      end

      it 'checks an actions-only edit against the stored deployment trigger' do
        actions = [{ 'type' => 'require_approval', 'value' => { 'roles' => %w[release_manager deployment_observer] } }]

        expect(repository.update(stored_policy.id, { actions: actions }).actions).to eq(actions)
      end

      it 'raises ValidationError when the trigger moves off deployment triggers' do
        expect { repository.update(stored_policy.id, { trigger_type: 'project.before_settings_update' }) }
          .to raise_error(Gitlab::PolicyStore::ValidationError,
            'action 0: CD roles (release_manager) can only be used with deployment triggers')
      end
    end

    context 'with a stored group policy on a trigger without a group hierarchy' do
      let(:stored_policy) { create(:govern_policy, namespace: group, trigger_type: :deployment_requested) }

      it 'leaves an edit that does not touch the trigger' do
        expect(repository.update(stored_policy.id, { name: 'Renamed policy' }).name).to eq('Renamed policy')
      end

      it 'raises ValidationError when the trigger changes to another one without a group hierarchy' do
        expect { repository.update(stored_policy.id, { trigger_type: 'deployment_promoted' }) }
          .to raise_error(Gitlab::PolicyStore::ValidationError,
            "trigger_type deployment_promoted cannot be used by a namespace's policy")
      end

      it 'accepts moving it onto a trigger with a group hierarchy' do
        expect(repository.update(stored_policy.id, { trigger_type: 'project.after_create' }).trigger_type)
          .to eq('project.after_create')
      end
    end

    it 'raises NotFound when the policy is deleted between the read and the lock' do
      id = policy.id
      allow_next_found_instance_of(Govern::Policy) do |record|
        allow(record).to receive(:with_lock).and_raise(ActiveRecord::RecordNotFound)
      end

      expect { repository.update(id, { name: 'Renamed' }) }
        .to raise_error(Gitlab::PolicyStore::NotFound, "Policy with id #{id} was not found")
    end

    # Create compiles from the caller's Hash and the rename recompiles from jsonb, so only
    # the round trip proves the two agree on more than the name.
    it 'recompiles a scope authored with symbol values without changing what it matches' do
      created = repository.create(organization_id: organization_id, name: 'Original name',
        trigger_type: 'deployment_requested',
        policy_scope: { match_mode: :any, groups: { including: [{ id: 10 }] } })

      updated = repository.update(created.id, name: 'Renamed policy')

      expect(updated.scope_rego).to include('Renamed policy')
      expect(updated.scope_rego.gsub('Renamed policy', 'Original name')).to eq(created.scope_rego)
    end

    it 'recomputes scope_dimensions when an update recompiles the scope' do
      created = repository.create(organization_id: organization_id, name: 'Originally scoped',
        trigger_type: 'deployment_requested', policy_scope: { compliance_frameworks: [{ id: 5 }] })

      updated = repository.update(created.id, policy_scope: { groups: { including: [{ id: 3 }] } })

      expect(updated.scope_dimensions).to eq(['groups'])
    end

    it 'generates a program on rename for a policy stored without one' do
      record = create(:govern_policy, namespace: group, scope_rego: nil, name: 'Original name')

      updated = repository.update(record.id, name: 'Renamed policy')

      expect(updated.scope_rego).to include('Renamed policy')
    end

    it 'leaves the row and its version untouched when a replacement rule does not parse', :aggregate_failures do
      expect { repository.update(policy.id, rules: [broken_rule]) }
        .to raise_error(Gitlab::PolicyStore::ValidationError, /\Arules\[0\] is invalid/)

      expect(Govern::Policy.find(policy.id)).to have_attributes(version: policy.version, rules: policy.rules)
    end
  end
end
# rubocop:enable Rails/SaveBang
