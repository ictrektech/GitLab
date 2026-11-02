# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::Impact::Draft, feature_category: :security_policy_management do
  let_it_be(:group) { create(:group) }

  subject(:draft) do
    described_class.build(
      organization_id: group.organization_id, namespace_id: group.id,
      policy_scope: { 'projects' => {} }, rules: [{ 'type' => 'custom', 'value' => 'package governance' }]
    )
  end

  it 'carries what the editor authored', :aggregate_failures do
    expect(draft).to have_attributes(
      organization_id: group.organization_id, namespace_id: group.id, policy_scope: { 'projects' => {} }
    )
    expect(draft.rules).to contain_exactly({ 'type' => 'custom', 'value' => 'package governance' })
  end

  it 'is an unsaved, read-only policy that refuses to be persisted', :aggregate_failures do
    expect(draft).to be_a(Govern::Policy).and be_new_record.and be_readonly
    expect { draft.save!(validate: false) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(Govern::Policy.count).to eq(0)
  end
end
