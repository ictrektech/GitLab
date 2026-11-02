# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onboarding::FeatureLibrary::ExplorePagesBuilder, feature_category: :onboarding do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let(:catalog) { Onboarding::FeatureLibrary::Catalog }
  let(:base_plan) { :free }
  let(:deployment) { :saas }
  let(:plan_context) do
    instance_double(
      Onboarding::FeatureLibrary::CurrentPlanContext,
      to_h: { edition: :ee, deployment: deployment, current_plan: base_plan, base_plan: base_plan, trial: false },
      tier_pages: Onboarding::FeatureLibrary::CurrentPlanContext::PLANS.drop(
        Onboarding::FeatureLibrary::CurrentPlanContext::PLANS.index(base_plan) + 1
      ),
      base_plan: base_plan,
      deployment: deployment
    )
  end

  let(:cta) { { type: 'upgrade', text: 'Upgrade', url: 'https://example.com' } }
  let(:premium_item) { nav_item }
  let(:ultimate_item) { nav_item(item_id: :security_dashboard, tier: :ultimate, docs_path: 'user/x.md#reports') }
  let(:add_on_item) { nav_item(item_id: :ai_agents, category: :duo_agents_menu, tier: :add_on) }
  let(:enhanced_item) do
    nav_item(item_id: :labels, category: :manage_menu, tier: :free, licensed_features: [],
      enhancements: { premium: 'Scoped labels', ultimate: 'Custom fields' })
  end

  let(:premium_only_enhanced_item) do
    nav_item(item_id: :milestones, category: :plan_menu, tier: :free, licensed_features: [],
      enhancements: { premium: 'Burndown charts' })
  end

  let(:premium_highlight) { capability }
  let(:ultimate_highlight) { capability(id: :advanced_sast, tier: :ultimate) }
  let(:credits) { capability(id: :duo_agent_platform, tier: :add_on) }
  let(:compute_minutes) do
    capability(id: :compute_minutes_premium, title: 'Compute minutes',
      description: 'Get %{plan_minutes} a month, up from %{base_minutes} on %{base_plan}',
      description_variables: %i[plan_minutes base_minutes base_plan])
  end

  def nav_item(**attributes)
    catalog::NavItem.new(
      item_id: :audit_events, panel: :group, category: :secure_menu, tier: :premium,
      licensed_features: [:audit_events], title: 'Audit events', description: 'Track changes',
      icon: 'audit-events', docs_path: 'user/compliance/audit_events.md', **attributes
    )
  end

  def capability(**attributes)
    catalog::Capability.new(
      id: :merge_controls, panel: :group, tier: :premium, title: 'Merge controls',
      description: 'Require approvals', icon: 'code', docs_path: 'ci/pipelines/merge_trains.md', **attributes
    )
  end

  subject(:result) { described_class.new(user: user, resource: group, panel: 'group').execute }

  before do
    allow(Onboarding::FeatureLibrary::CurrentPlanContext).to receive(:new).with(resource: group)
      .and_return(plan_context)
    allow(Onboarding::FeatureLibrary::UpgradeCta).to receive(:new)
      .and_return(instance_double(Onboarding::FeatureLibrary::UpgradeCta, build: cta))
    allow(catalog).to receive_messages(
      nav_items: [premium_item, ultimate_item, add_on_item, enhanced_item, premium_only_enhanced_item],
      capabilities: [premium_highlight, ultimate_highlight, credits, compute_minutes]
    )
  end

  def page(plan)
    result[:pages].find { |entry| entry[:plan] == plan }
  end

  def item_ids(plan)
    page(plan)[:categories].flat_map { |category| category[:items].map { |item| [item[:id], item[:label][:type]] } }
  end

  it 'provides a value for every supported description variable' do
    expect(described_class::VARIABLE_PROVIDERS.keys).to match_array(catalog::DESCRIPTION_VARIABLES)
  end

  it 'has compute minutes for every plan' do
    expect(described_class::COMPUTE_MINUTES.keys).to eq(Onboarding::FeatureLibrary::CurrentPlanContext::PLANS)
  end

  it 'returns the plan context and one page per upgrade tier', :aggregate_failures do
    expect(result[:current_plan_context]).to eq(plan_context.to_h)
    expect(result[:pages].map { |entry| entry[:plan] }).to eq(%i[premium ultimate])
  end

  it 'attaches the page CTA built for the page plan and base plan' do
    expect(page(:ultimate)[:cta]).to eq(cta)
    expect(Onboarding::FeatureLibrary::UpgradeCta)
      .to have_received(:new).with(user: user, resource: group, plan: :ultimate, base_plan: :free)
  end

  it 'serializes highlights and credits as capability items', :aggregate_failures do
    expect(page(:premium)[:highlights].map { |item| item[:id] }).to eq(%i[merge_controls compute_minutes_premium])
    expect(page(:premium)[:credits]).to contain_exactly(
      a_hash_including(id: :duo_agent_platform, source: 'capability', label: { type: 'add_on', plan: :premium })
    )
    expect(page(:premium)[:highlights].first).to include(
      source: 'capability', title: 'Merge controls', description: 'Require approvals', icon: 'code',
      docs_url: '/help/ci/pipelines/merge_trains.md', label: { type: 'new', plan: :premium }
    )
  end

  it 'fills the compute minutes copy from the page plan and base plan' do
    expect(page(:premium)[:highlights].last[:description]).to eq('Get 10,000 a month, up from 400 on Free')
  end

  it 'groups nav items by category in sidebar order with translated titles', :aggregate_failures do
    categories = page(:ultimate)[:categories]

    expect(categories.map { |category| category[:id] }).to eq(%i[manage_menu plan_menu duo_agents_menu secure_menu])
    expect(categories.map { |category| category[:title] }).to eq(%w[Manage Plan AI Secure])
    expect(categories.flat_map { |category| category[:items] }.map(&:keys))
      .to all(contain_exactly(:id, :source, :title, :description, :icon, :docs_url, :label))
  end

  it 'labels new, enhanced and add-on items with the page plan', :aggregate_failures do
    expect(item_ids(:premium)).to contain_exactly(
      [:audit_events, 'new'], [:ai_agents, 'add_on'], [:labels, 'enhanced'], [:milestones, 'enhanced']
    )
    expect(page(:premium)[:categories].flat_map { |category| category[:items] }.map { |item| item[:label][:plan] })
      .to all(eq(:premium))
  end

  it 'uses the enhancement text as the description of an enhanced item' do
    labels = page(:ultimate)[:categories].flat_map { |category| category[:items] }.find { |item| item[:id] == :labels }

    expect(labels).to include(
      source: 'nav_item', description: 'Custom fields', label: { type: 'enhanced', plan: :ultimate }
    )
  end

  it 'builds docs URLs with help_page_path, keeping anchors', :aggregate_failures do
    items = page(:ultimate)[:categories].flat_map { |category| category[:items] }

    expect(items.find { |item| item[:id] == :audit_events }[:docs_url]).to eq('/help/user/compliance/audit_events.md')
    expect(items.find { |item| item[:id] == :security_dashboard }[:docs_url]).to eq('/help/user/x.md#reports')
  end

  context 'when the viewer holds Premium' do
    let(:base_plan) { :premium }

    it 'returns only the Ultimate page' do
      expect(result[:pages].map { |entry| entry[:plan] }).to eq([:ultimate])
    end

    it 'drops items and enhancements the plan already includes, but keeps add-ons', :aggregate_failures do
      expect(item_ids(:ultimate)).to contain_exactly(
        [:security_dashboard, 'new'], [:ai_agents, 'add_on'], [:labels, 'enhanced']
      )
    end

    it 'compares compute minutes against Premium' do
      allow(catalog).to receive(:capabilities).and_return([
        ultimate_highlight, capability(id: :compute_minutes_ultimate, tier: :ultimate,
          description: 'Get %{plan_minutes} a month, up from %{base_minutes} on %{base_plan}',
          description_variables: %i[plan_minutes base_minutes base_plan])
      ])

      expect(page(:ultimate)[:highlights].last[:description]).to eq('Get 50,000 a month, up from 10,000 on Premium')
    end
  end

  context 'when the viewer holds Ultimate' do
    let(:base_plan) { :ultimate }

    it 'returns no pages' do
      expect(result[:pages]).to eq([])
    end
  end

  context 'on self-managed' do
    let(:deployment) { :self_managed }

    it 'reads the catalog for that deployment' do
      expect(catalog).to receive(:explore_pages).with(panel: :group, deployment: :self_managed).and_call_original

      result
    end
  end

  describe '.available?' do
    let_it_be(:member) { create(:user, guest_of: group) }

    it 'is false for the base implementation' do
      base = described_class.method(:available?)
      base = base.super_method while base.super_method

      expect(base.call(user: member, resource: group)).to be(false)
    end
  end
end
