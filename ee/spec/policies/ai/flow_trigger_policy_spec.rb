# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggerPolicy, feature_category: :dap_triggers do
  let_it_be(:group) { create(:group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }
  let_it_be(:project_trigger) { create(:ai_flow_trigger) }
  let_it_be_with_refind(:group_trigger) { create(:ai_flow_trigger, :for_inheritance_consumer, group: group) }

  describe 'delegation' do
    it { expect(described_class.new(nil, project_trigger)).to delegate_to(::ProjectPolicy) }
    it { expect(described_class.new(nil, group_trigger)).to delegate_to(::GroupPolicy) }
  end

  context 'with a group trigger' do
    subject(:policy) { described_class.new(maintainer, group_trigger) }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).and_return(true)
      allow(maintainer).to receive_messages(allowed_to_use?: true, allowed_to_use_through_namespace?: true)
    end

    it { expect_allowed(:read_ai_flow_triggers, :manage_ai_flow_triggers) }

    context 'when the inheritance record cannot be read' do
      before do
        NamespaceSetting.find_by(namespace_id: group.id).update!(duo_custom_flows_enabled: false)
      end

      it { expect_disallowed(:read_ai_flow_triggers, :manage_ai_flow_triggers) }
    end
  end
end
