# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Statuses::Lifecycles::Provider, feature_category: :team_planning do
  let_it_be(:namespace) { create(:group) }
  let_it_be(:other_namespace) { create(:group) }
  let_it_be(:issue_type) { build(:work_item_system_defined_type, :issue) }
  let_it_be(:task_type) { build(:work_item_system_defined_type, :task) }

  let(:system_defined_lifecycle) { issue_type.system_defined_lifecycle }

  before do
    stub_licensed_features(work_item_status: true)
  end

  subject(:provider) { described_class.new(namespace.id) }

  describe '#find_by_type' do
    context 'when a custom lifecycle is attached to the type in the namespace' do
      let_it_be(:custom_lifecycle) { create(:work_item_custom_lifecycle, namespace: namespace) }

      before do
        create(:work_item_type_custom_lifecycle,
          work_item_type: issue_type,
          namespace: namespace,
          lifecycle: custom_lifecycle)
      end

      it 'returns the custom lifecycle' do
        expect(provider.find_by_type(issue_type)).to eq(custom_lifecycle)
      end

      it 'returns the system-defined lifecycle for a type without a custom row' do
        expect(provider.find_by_type(task_type)).to eq(task_type.system_defined_lifecycle)
      end
    end

    context 'when no custom lifecycle is attached to the type in the namespace' do
      it 'returns the system-defined lifecycle' do
        expect(provider.find_by_type(issue_type)).to eq(system_defined_lifecycle)
      end

      it 'does not load the namespace for a type that is not flag-gated' do
        expect(::Namespace).not_to receive(:find_by_id)

        provider.find_by_type(issue_type)
      end
    end

    context 'when a custom lifecycle exists only in a different namespace' do
      let_it_be(:custom_lifecycle) { create(:work_item_custom_lifecycle, namespace: other_namespace) }

      before do
        create(:work_item_type_custom_lifecycle,
          work_item_type: issue_type,
          namespace: other_namespace,
          lifecycle: custom_lifecycle)
      end

      it 'returns the system-defined lifecycle' do
        expect(provider.find_by_type(issue_type)).to eq(system_defined_lifecycle)
      end
    end

    context 'when the namespace is nil' do
      subject(:provider) { described_class.new(nil) }

      it 'returns the system-defined lifecycle and does not raise' do
        expect(provider.find_by_type(issue_type)).to eq(system_defined_lifecycle)
      end
    end

    context 'when the type is a custom type converted from a system-defined type' do
      let_it_be(:converted_type) do
        create(:work_item_custom_type, :converted_from_issue, namespace: namespace)
      end

      let_it_be(:custom_lifecycle) { create(:work_item_custom_lifecycle, namespace: namespace) }

      before do
        create(:work_item_type_custom_lifecycle,
          work_item_type_id: converted_type.persistable_id,
          namespace: namespace,
          lifecycle: custom_lifecycle)
      end

      it 'resolves the converted custom type to the custom lifecycle' do
        expect(provider.find_by_type(converted_type)).to eq(custom_lifecycle)
      end

      it 'resolves the system-defined origin type to the same lifecycle' do
        expect(provider.find_by_type(issue_type)).to eq(custom_lifecycle)
      end
    end
  end

  describe '#find_custom_by_type' do
    context 'when a custom lifecycle is attached to the type in the namespace' do
      let_it_be(:custom_lifecycle) { create(:work_item_custom_lifecycle, namespace: namespace) }

      before do
        create(:work_item_type_custom_lifecycle,
          work_item_type: issue_type,
          namespace: namespace,
          lifecycle: custom_lifecycle)
      end

      it 'returns the custom lifecycle' do
        expect(provider.find_custom_by_type(issue_type)).to eq(custom_lifecycle)
      end

      it 'returns nil for a type without a custom row' do
        expect(provider.find_custom_by_type(task_type)).to be_nil
      end

      context 'when the status license is unavailable' do
        before do
          stub_licensed_features(work_item_status: false)
        end

        it 'still returns the attached custom lifecycle' do
          expect(provider.find_custom_by_type(issue_type)).to eq(custom_lifecycle)
        end
      end
    end

    context 'when no custom lifecycle is attached to the type in the namespace' do
      it 'returns nil' do
        expect(provider.find_custom_by_type(issue_type)).to be_nil
      end
    end

    context 'when the namespace is nil' do
      subject(:provider) { described_class.new(nil) }

      it 'returns nil and does not raise' do
        expect(provider.find_custom_by_type(issue_type)).to be_nil
      end
    end
  end

  describe 'index caching' do
    let_it_be(:custom_lifecycle) { create(:work_item_custom_lifecycle, namespace: namespace) }

    before do
      create(:work_item_type_custom_lifecycle,
        work_item_type: issue_type,
        namespace: namespace,
        lifecycle: custom_lifecycle)
    end

    it 'does not issue more queries when more types are indexed', :request_store do
      control = ActiveRecord::QueryRecorder.new do
        described_class.new(namespace.id).find_custom_by_type(issue_type)
      end

      task_lifecycle = create(:work_item_custom_lifecycle, namespace: namespace)
      create(:work_item_type_custom_lifecycle,
        work_item_type: task_type,
        namespace: namespace,
        lifecycle: task_lifecycle)

      expect do
        described_class.new(namespace.id).find_custom_by_type(issue_type)
      end.not_to exceed_query_limit(control)
    end

    it 'builds the index once per namespace per request', :request_store do
      provider.find_custom_by_type(issue_type)

      control = ActiveRecord::QueryRecorder.new do
        provider.find_custom_by_type(issue_type)
        provider.find_custom_by_type(task_type)
        described_class.new(namespace.id).find_custom_by_type(issue_type)
      end

      expect(control.count).to eq(0)
    end
  end

  describe 'masking for status-capable types behind a feature flag' do
    let_it_be(:epic_type) { build(:work_item_system_defined_type, :epic) }

    before do
      stub_licensed_features(work_item_status: true, epics: true)
    end

    context 'in a namespace that uses custom lifecycles' do
      let_it_be(:issue_lifecycle) { create(:work_item_custom_lifecycle, namespace: namespace) }

      before do
        create(:work_item_type_custom_lifecycle,
          work_item_type: issue_type,
          namespace: namespace,
          lifecycle: issue_lifecycle)
      end

      it 'masks the epic to the same lifecycle as the issue type' do
        expect(provider.find_by_type(epic_type)).to eq(issue_lifecycle)
        expect(provider.find_custom_by_type(epic_type)).to eq(issue_lifecycle)
      end

      context 'when the status license is unavailable' do
        before do
          stub_licensed_features(work_item_status: false, epics: true)
        end

        it 'still masks the epic to the issue lifecycle instead of the system-defined one' do
          expect(provider.find_by_type(epic_type)).to eq(issue_lifecycle)
        end
      end

      context 'when the epic status flag is disabled' do
        before do
          stub_feature_flags(work_item_status_for_epics: false)
        end

        it 'resolves nil for the epic (fully dormant)' do
          expect(provider.find_custom_by_type(epic_type)).to be_nil
          expect(provider.find_by_type(epic_type)).to be_nil
        end
      end
    end

    context 'when the issue type has no custom row but the namespace does' do
      let_it_be(:other_lifecycle) { create(:work_item_custom_lifecycle, namespace: namespace) }

      before do
        create(:work_item_type_custom_lifecycle,
          work_item_type: task_type,
          namespace: namespace,
          lifecycle: other_lifecycle)
      end

      it 'masks the epic to the first available custom lifecycle' do
        expect(provider.find_by_type(epic_type)).to eq(other_lifecycle)
      end

      context 'when the issue type cannot be resolved' do
        before do
          allow_next_instance_of(::WorkItems::TypesFramework::Provider) do |types_provider|
            allow(types_provider).to receive(:default_issue_type).and_return(nil)
          end
        end

        it 'masks the epic to the first available custom lifecycle' do
          expect(provider.find_by_type(epic_type)).to eq(other_lifecycle)
        end
      end
    end

    context 'when the namespace is nil' do
      subject(:provider) { described_class.new(nil) }

      it 'resolves nil for the epic' do
        expect(provider.find_by_type(epic_type)).to be_nil
      end
    end

    context 'in a namespace that uses the system-defined lifecycle' do
      it 'falls through to the system-defined lifecycle for the epic' do
        expect(provider.find_by_type(epic_type)).to eq(epic_type.system_defined_lifecycle)
      end

      context 'when the epic status flag is disabled' do
        before do
          stub_feature_flags(work_item_status_for_epics: false)
        end

        it 'resolves nil for the epic' do
          expect(provider.find_by_type(epic_type)).to be_nil
        end
      end
    end
  end

  describe '#types_for and #masked_types_for' do
    let_it_be(:epic_type) { build(:work_item_system_defined_type, :epic) }
    let_it_be(:ticket_type) { build(:work_item_system_defined_type, :ticket) }
    # Reloaded per example so the type_custom_lifecycles association cache does
    # not leak rows created in one example into the next.
    let_it_be_with_reload(:issue_lifecycle) { create(:work_item_custom_lifecycle, namespace: namespace) }
    let_it_be_with_reload(:other_lifecycle) { create(:work_item_custom_lifecycle, namespace: namespace) }

    before do
      stub_licensed_features(work_item_status: true, epics: true)

      create(:work_item_type_custom_lifecycle,
        work_item_type: issue_type,
        namespace: namespace,
        lifecycle: issue_lifecycle)
      create(:work_item_type_custom_lifecycle,
        work_item_type: task_type,
        namespace: namespace,
        lifecycle: other_lifecycle)
    end

    it 'includes the masked epic and ticket only for the lifecycle they are masked to', :aggregate_failures do
      expect(provider.types_for(issue_lifecycle)).to contain_exactly(issue_type, epic_type, ticket_type)
      expect(provider.masked_types_for(issue_lifecycle)).to contain_exactly(epic_type, ticket_type)

      expect(provider.types_for(other_lifecycle)).to contain_exactly(task_type)
      expect(provider.masked_types_for(other_lifecycle)).to be_empty
    end

    context 'when the epic has a direct row' do
      before do
        create(:work_item_type_custom_lifecycle,
          work_item_type: epic_type,
          namespace: namespace,
          lifecycle: other_lifecycle)
      end

      it 'lists the epic as attached and no longer masked, leaving the ticket masked', :aggregate_failures do
        expect(provider.types_for(issue_lifecycle)).to contain_exactly(issue_type, ticket_type)
        expect(provider.masked_types_for(issue_lifecycle)).to contain_exactly(ticket_type)

        expect(provider.types_for(other_lifecycle)).to contain_exactly(task_type, epic_type)
      end
    end

    context 'when the epic status flag is disabled' do
      before do
        stub_feature_flags(work_item_status_for_epics: false)
      end

      it 'returns the attached types and the still-masked ticket', :aggregate_failures do
        expect(provider.types_for(issue_lifecycle)).to contain_exactly(issue_type, ticket_type)
        expect(provider.masked_types_for(issue_lifecycle)).to contain_exactly(ticket_type)
      end
    end

    context 'when the ticket status flag is disabled' do
      before do
        stub_feature_flags(work_item_ticket_migration: false)
      end

      it 'returns the attached types and the still-masked epic', :aggregate_failures do
        expect(provider.types_for(issue_lifecycle)).to contain_exactly(issue_type, epic_type)
        expect(provider.masked_types_for(issue_lifecycle)).to contain_exactly(epic_type)
      end
    end

    context 'when both the epic and ticket status flags are disabled' do
      before do
        stub_feature_flags(work_item_status_for_epics: false, work_item_ticket_migration: false)
      end

      it 'returns only the attached types', :aggregate_failures do
        expect(provider.types_for(issue_lifecycle)).to contain_exactly(issue_type)
        expect(provider.masked_types_for(issue_lifecycle)).to be_empty
      end
    end

    context 'when the status license is unavailable' do
      before do
        stub_licensed_features(work_item_status: false, epics: true)
      end

      it 'does not list the epic as masked, matching what ensure_connection! can persist' do
        expect(provider.masked_types_for(issue_lifecycle)).to be_empty
      end
    end

    context 'without a root namespace' do
      subject(:provider) { described_class.new(nil) }

      it 'returns only the attached types', :aggregate_failures do
        expect(provider.types_for(issue_lifecycle)).to contain_exactly(issue_type)
        expect(provider.masked_types_for(issue_lifecycle)).to be_empty
      end
    end

    context 'in a system-defined-lifecycle namespace' do
      subject(:provider) { described_class.new(other_namespace.id) }

      it 'returns no masked types' do
        expect(provider.masked_types_for(issue_lifecycle)).to be_empty
      end
    end
  end

  describe '#ensure_connection!' do
    let_it_be(:epic_type) { build(:work_item_system_defined_type, :epic) }
    let_it_be(:issue_lifecycle) { create(:work_item_custom_lifecycle, namespace: namespace) }

    before do
      stub_licensed_features(work_item_status: true, epics: true)

      create(:work_item_type_custom_lifecycle,
        work_item_type: issue_type,
        namespace: namespace,
        lifecycle: issue_lifecycle)
    end

    it 'persists the masked connection on the first call and is idempotent', :aggregate_failures do
      expect { provider.ensure_connection!(epic_type) }
        .to change { ::WorkItems::TypeCustomLifecycle.with_namespace_id(namespace.id).count }.by(1)

      row = ::WorkItems::TypeCustomLifecycle
        .with_namespace_id(namespace.id)
        .find_by(work_item_type_id: epic_type.persistable_id)
      expect(row.lifecycle).to eq(issue_lifecycle)

      expect { described_class.new(namespace.id).ensure_connection!(epic_type) }
        .not_to change { ::WorkItems::TypeCustomLifecycle.with_namespace_id(namespace.id).count }
    end

    it 'returns false and persists nothing for a type that already has a direct row' do
      expect(provider.ensure_connection!(issue_type)).to be(false)
    end

    context 'when a concurrent write lands between the index read and the insert' do
      before do
        allow(::WorkItems::TypeCustomLifecycle).to receive(:create!).and_wrap_original do |original, **attrs|
          original.call(**attrs)
          raise ActiveRecord::RecordInvalid
        end
      end

      it 'treats the uniqueness validation failure as a successful connection' do
        expect(provider.ensure_connection!(epic_type)).to be(true)
      end
    end

    context 'when the insert fails validation for another reason' do
      before do
        allow(::WorkItems::TypeCustomLifecycle).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      end

      it 're-raises' do
        expect { provider.ensure_connection!(epic_type) }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    it 'returns false and persists nothing for a non-flag-gated type without a direct row', :aggregate_failures do
      expect { expect(provider.ensure_connection!(task_type)).to be(false) }
        .not_to change { ::WorkItems::TypeCustomLifecycle.with_namespace_id(namespace.id).count }
    end

    context 'when the epic status flag is disabled' do
      before do
        stub_feature_flags(work_item_status_for_epics: false)
      end

      it 'does not persist a connection' do
        expect { provider.ensure_connection!(epic_type) }
          .not_to change { ::WorkItems::TypeCustomLifecycle.with_namespace_id(namespace.id).count }
      end
    end

    context 'in a system-defined-lifecycle namespace' do
      subject(:provider) { described_class.new(other_namespace.id) }

      it 'does not persist a connection' do
        expect { provider.ensure_connection!(epic_type) }
          .not_to change { ::WorkItems::TypeCustomLifecycle.with_namespace_id(other_namespace.id).count }
      end
    end

    context 'when the root namespace cannot be loaded' do
      before do
        allow(::Namespace).to receive(:find_by_id).with(namespace.id).and_return(nil)
      end

      it 'returns false' do
        expect(provider.ensure_connection!(epic_type)).to be(false)
      end
    end

    context 'without a root namespace' do
      subject(:provider) { described_class.new(nil) }

      it 'returns false' do
        expect(provider.ensure_connection!(epic_type)).to be(false)
      end
    end
  end
end
