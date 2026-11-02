# frozen_string_literal: true

require 'spec_helper'

# Keeps the CE Feature catalog in step with the EE sidebar: the nav is the source of truth
# for which items are paid, and for their tier, title, description, icon and category.
# GitlabSubscriptions::Features checks paid tiers too: a nav item's tier is the lowest plan of its licensed
# features, and each licensed feature of a capability must first be available on its tier.
# On failure, update lib/onboarding/feature_library/catalog/<panel>_panel.rb, which explains each field.
RSpec.describe Onboarding::FeatureLibrary::Catalog, feature_category: :onboarding do
  let_it_be(:owner) { create(:user) }
  let_it_be(:group) { create(:group, owners: owner) }
  let_it_be(:project) { create(:project, :small_repo, group: group) }

  # Same class the modal filters on (HIDDEN_NAV_ITEM_CLASS in super_sidebar/constants.js).
  let(:hidden_nav_item_class) { 'js-super-sidebar-nav-item-hidden' }

  before do
    # Contribution analytics is only rendered while its replacement dashboard is off.
    stub_feature_flags(contributions_analytics_dashboard: false)
    # Tracing, Metrics and Logs are a work-in-progress feature; they join the catalog once it ships.
    stub_feature_flags(observability_features: false)
    # Incidents is hidden for the few projects in the incident management deprecation rollout.
    stub_feature_flags(hide_incident_management_features: false)
    # Premium pipeline analytics is a work-in-progress feature, so group CI/CD analytics needs Ultimate.
    stub_feature_flags(group_ci_cd_analytics_pipelines_ff: false)
  end

  def build_panel(panel)
    case panel
    when :group
      context = Sidebars::Groups::Context.new(
        current_user: owner, container: Group.find(group.id), is_super_sidebar: true,
        show_promotions: false, show_discover_group_security: false
      )
      Sidebars::Groups::SuperSidebarPanel.new(context)
    when :project
      fresh_project = Project.find(project.id)
      context = Sidebars::Projects::Context.new(
        current_user: owner, current_ref: fresh_project.default_branch, is_super_sidebar: true,
        show_promotions: false, can_view_pipeline_editor: true, show_cluster_hint: false,
        show_discover_project_security: false, learn_gitlab_enabled: false, show_get_started_menu: false,
        jira_issues_integration: false, container: fresh_project
      )
      Sidebars::Projects::SuperSidebarPanel.new(context)
    end
  end

  # Rendered nav items keyed by id, each tagged with the category menu it rendered under.
  # Mirrors the Feature catalog modal: only its categories count, and hidden items are skipped.
  def rendered_items(panel, licensed:)
    Gitlab::SafeRequestStore.clear!
    stub_licensed_features(GitlabSubscriptions::Features::ALL_FEATURES.index_with(licensed))

    build_panel(panel).super_sidebar_menu_items.each_with_object({}) do |menu, items|
      next unless described_class::CATEGORIES.key?(menu[:id].to_sym)

      Array(menu[:items]).each do |item|
        next if item[:link_classes].to_s.include?(hidden_nav_item_class)

        items[item[:id].to_sym] = item.merge(category: menu[:id].to_sym)
      end
    end
  end

  def panel_file(panel)
    "lib/onboarding/feature_library/catalog/#{panel}_panel.rb"
  end

  def minimum_tier(licensed_features)
    plans = licensed_features.filter_map { |feature| GitlabSubscriptions::Features.minimum_plan_for(feature) }
    plan = plans.min_by { |name| License::EE_ALL_PLANS.index(name) }

    plan && EE::Sidebars::Menu::LEGACY_PLAN_TIERS.fetch(plan, plan.to_sym)
  end

  describe 'category titles' do
    it 'match the super sidebar menu titles', :aggregate_failures do
      stub_licensed_features(GitlabSubscriptions::Features::ALL_FEATURES.index_with(true))

      menu_titles = described_class::PANELS.flat_map do |panel|
        build_panel(panel).super_sidebar_menu_items.map { |menu| [menu[:id].to_sym, menu[:title]] }
      end.to_h

      described_class::CATEGORIES.each do |category, msgid|
        expect(menu_titles[category]).to eq(s_(msgid)),
          "#{category}: nav title #{menu_titles[category].inspect} (nil when the menu did not render), " \
            "catalog title #{s_(msgid).inspect}"
      end
    end
  end

  describe 'tiers' do
    let(:paid_tiers) { %i[premium ultimate] }

    # GitLab.com plan limits and quotas, which no licensed feature gates.
    let(:capabilities_without_licensed_features) { %i[runner_limits compute_minutes_premium compute_minutes_ultimate] }

    # minimum_tier skips unknown features, so a renamed one would otherwise go unnoticed.
    it 'only lists licensed features that exist', :aggregate_failures do
      entries = described_class.nav_items.map { |item| [item, item.item_id] } +
        described_class.capabilities.map { |capability| [capability, capability.id] }

      entries.each do |entry, id|
        unknown = entry.licensed_features.reject { |feature| GitlabSubscriptions::Features.minimum_plan_for(feature) }

        expect(unknown).to be_empty, "#{entry.panel}/#{id}: unknown licensed features " \
          "#{unknown.inspect} (update #{panel_file(entry.panel)})"
      end
    end

    it 'stores the lowest plan of each nav item licensed features', :aggregate_failures do
      described_class.nav_items.select { |item| paid_tiers.include?(item.tier) }.each do |item|
        expect(item.tier).to eq(minimum_tier(item.licensed_features)),
          "#{item.panel}/#{item.item_id}: stored tier #{item.tier.inspect}, " \
            "licensed features #{item.licensed_features.inspect} are #{minimum_tier(item.licensed_features).inspect}"
      end
    end

    # A capability card promises all its licensed features, so each one must need exactly its tier.
    it 'stores the plan of every capability licensed feature', :aggregate_failures do
      described_class.capabilities.select { |capability| paid_tiers.include?(capability.tier) }.each do |capability|
        next if capabilities_without_licensed_features.include?(capability.id)

        feature_tiers = capability.licensed_features.index_with { |feature| minimum_tier([feature]) }

        expect(feature_tiers.values).to be_present.and(all(eq(capability.tier))),
          "#{capability.panel}/#{capability.id}: stored tier #{capability.tier.inspect}, " \
            "licensed feature tiers #{feature_tiers.inspect} (update #{panel_file(capability.panel)}, " \
            "or exempt a GitLab.com limit in capabilities_without_licensed_features)"
      end
    end

    it 'only exempts capabilities that exist and have no licensed features', :aggregate_failures do
      exempt = described_class.capabilities.select do |capability|
        capabilities_without_licensed_features.include?(capability.id)
      end

      expect(exempt.map(&:id)).to include(*capabilities_without_licensed_features)
      exempt.each do |capability|
        expect(capability.licensed_features).to be_empty, "#{capability.panel}/#{capability.id} is exempt"
      end
    end

    it 'lists no licensed features on add-on capabilities', :aggregate_failures do
      described_class.capabilities.reject { |capability| paid_tiers.include?(capability.tier) }.each do |capability|
        expect(capability.licensed_features).to be_empty,
          "#{capability.panel}/#{capability.id}: only Premium and Ultimate highlights list licensed features"
      end
    end
  end

  shared_examples 'catalog nav items matching the sidebar' do |panel, deployment, content_pending:|
    let(:entries) do
      described_class.nav_items.select { |item| item.panel == panel && item.shown_on_deployments.include?(deployment) }
    end

    let(:licensed_items) { rendered_items(panel, licensed: true) }

    it 'copies the nav item title, description, icon, category and tier', :aggregate_failures do
      entries.each do |entry|
        rendered = licensed_items[entry.item_id]
        next unless rendered

        {
          title: [entry.translated_title, rendered[:title]],
          description: [entry.translated_description, rendered[:description]],
          icon: [entry.icon, rendered[:library_icon] || rendered[:icon]],
          category: [entry.category, rendered[:category]],
          tier: [entry.tier, rendered[:tier] || :free]
        }.each do |field, (catalog_value, nav_value)|
          expect(catalog_value).to eq(nav_value),
            "#{panel}/#{entry.item_id} #{field}: catalog #{catalog_value.inspect}, nav #{nav_value.inspect} " \
              "(update #{panel_file(panel)})"
        end
      end
    end

    # An entry limited to other deployments counts: excluding an item from a deployment is
    # a deliberate content decision recorded in the entry.
    it 'has an entry for every nav item that needs a paid plan' do
      pending("#{panel} content is added in a follow-up MR") if content_pending

      paid_ids = licensed_items.keys - rendered_items(panel, licensed: false).keys
      missing = paid_ids - described_class.nav_items.select { |item| item.panel == panel }.map(&:item_id)

      expect(missing).to be_empty,
        "#{panel} nav items without a catalog entry (#{deployment}): #{missing.join(', ')} " \
          "(add them to #{panel_file(panel)})"
    end

    it 'only has entries for nav items that render' do
      unknown = entries.map(&:item_id) - licensed_items.keys

      expect(unknown).to be_empty, "#{panel} catalog entries with no rendered nav item (#{deployment}): " \
        "#{unknown.join(', ')} (update #{panel_file(panel)})"
    end
  end

  context 'on self-managed' do
    it_behaves_like 'catalog nav items matching the sidebar', :group, :self_managed, content_pending: false
    it_behaves_like 'catalog nav items matching the sidebar', :project, :self_managed, content_pending: false
  end

  context 'on GitLab.com', :saas, :saas_group_credentials_inventory do
    before do
      # Rendering the Secrets Manager item asks CustomersDot for trial state; unknown is fine here.
      stub_request(:get, %r{/api/v1/billing/usage/trials}).to_return(status: 404)
    end

    it_behaves_like 'catalog nav items matching the sidebar', :group, :saas, content_pending: false
    it_behaves_like 'catalog nav items matching the sidebar', :project, :saas, content_pending: false
  end
end
