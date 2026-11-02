# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::CustomDashboards::DashboardConstraints, feature_category: :custom_dashboards_foundation do
  describe '.satisfied?' do
    subject(:satisfied) { described_class.satisfied?(dashboard, user) }

    let_it_be(:user) { create(:user) }

    let(:dashboard) do
      Analytics::CustomDashboards::SystemDashboard.new(slug: 'test', config: config)
    end

    context 'when the dashboard declares no constraints' do
      let(:config) { { 'title' => 'Test' } }

      it { is_expected.to be(true) }
    end

    # Each shape fails the schema, and a dashboard is kept with its schema errors, so they
    # reach the policy. A dashboard whose gating cannot be read must stay hidden.
    context 'when constraints is not a mapping, or is an empty one' do
      using RSpec::Parameterized::TableSyntax

      let(:config) { { 'title' => 'Test', 'constraints' => value } }

      where(:value) { ['clickhouse', false, nil, {}] }

      with_them do
        it 'raises in development so the typo cannot silently pass' do
          expect { satisfied }.to raise_error(ArgumentError, /Unknown constraints/)
        end

        context 'in production' do
          before do
            allow(::Gitlab).to receive(:dev_or_test_env?).and_return(false)
          end

          it { is_expected.to be(false) }
        end
      end
    end

    context 'when constraints has a key the schema does not know' do
      let(:config) { { 'title' => 'Test', 'constraints' => { 'licence' => 'ai_analytics' } } }

      it 'raises in development so the typo cannot silently pass' do
        expect { satisfied }.to raise_error(ArgumentError, /Unknown constraints.*licence/)
      end

      context 'in production' do
        before do
          allow(::Gitlab).to receive(:dev_or_test_env?).and_return(false)
        end

        it { is_expected.to be(false) }
      end
    end

    # A present key with a value the schema rejects must hide the dashboard, never read as absent.
    describe 'a constraint present with a value the schema rejects' do
      using RSpec::Parameterized::TableSyntax

      let(:config) { { 'title' => 'Test', 'constraints' => { kind => value } } }

      where(:kind, :value) do
        'license'      | false
        'license'      | nil
        'feature_flag' | false
        'feature_flag' | nil
        'data'         | false
        'data'         | nil
        'data'         | []
        'data'         | 'clickhouse'
      end

      with_them do
        it 'raises in development so the typo cannot silently pass' do
          expect { satisfied }.to raise_error(ArgumentError, /Unknown #{kind} constraint/)
        end

        context 'in production' do
          before do
            allow(::Gitlab).to receive(:dev_or_test_env?).and_return(false)
            allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
            stub_feature_flags(dap_impact_v1: true)
          end

          it { is_expected.to be(false) }
        end
      end
    end

    describe 'data' do
      let(:config) { { 'title' => 'Test', 'constraints' => { 'data' => ['clickhouse'] } } }

      before do
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(enabled)
      end

      context 'when ClickHouse is enabled for analytics' do
        let(:enabled) { true }

        it { is_expected.to be(true) }
      end

      context 'when ClickHouse is not enabled for analytics' do
        let(:enabled) { false }

        it { is_expected.to be(false) }
      end

      context 'when the dashboard declares an unknown data source' do
        let(:config) { { 'title' => 'Test', 'constraints' => { 'data' => ['nope'] } } }
        let(:enabled) { true }

        it 'raises in development so the typo cannot silently pass' do
          expect { satisfied }.to raise_error(ArgumentError, /Unknown data constraint/)
        end

        context 'in production' do
          before do
            allow(::Gitlab).to receive(:dev_or_test_env?).and_return(false)
          end

          # The loader already reported the schema error once per load; reporting again here
          # would fire once per dashboard, per user, per request.
          it 'hides the dashboard without reporting again' do
            expect(Gitlab::ErrorTracking).not_to receive(:track_exception)
            expect(Gitlab::ErrorTracking).not_to receive(:track_and_raise_for_dev_exception)

            expect(satisfied).to be(false)
          end
        end
      end
    end

    describe 'license' do
      let(:config) { { 'title' => 'Test', 'constraints' => { 'license' => 'product_analytics' } } }

      context 'when the licence name is not a string' do
        let(:config) { { 'title' => 'Test', 'constraints' => { 'license' => 123 } } }

        it 'raises in development so the typo cannot silently pass' do
          expect { satisfied }.to raise_error(ArgumentError, /Unknown license constraint/)
        end

        context 'in production' do
          before do
            allow(::Gitlab).to receive(:dev_or_test_env?).and_return(false)
          end

          it { is_expected.to be(false) }
        end
      end

      context 'when the licence names a licensed feature the schema does not allow' do
        let(:config) { { 'title' => 'Test', 'constraints' => { 'license' => 'ai_analytics' } } }

        before do
          stub_licensed_features(ai_analytics: true)
        end

        it 'raises in development' do
          expect { satisfied }.to raise_error(ArgumentError, /Unknown license constraint/)
        end

        context 'in production' do
          before do
            allow(::Gitlab).to receive(:dev_or_test_env?).and_return(false)
          end

          it { is_expected.to be(false) }
        end
      end

      context 'when the licence includes the feature' do
        before do
          stub_licensed_features(product_analytics: true)
        end

        it { is_expected.to be(true) }
      end

      context 'when the licence does not include the feature' do
        before do
          stub_licensed_features(product_analytics: false)
        end

        it { is_expected.to be(false) }
      end
    end

    describe 'feature_flag' do
      let(:config) { { 'title' => 'Test', 'constraints' => { 'feature_flag' => 'dap_impact_v1' } } }

      context 'when the flag is enabled for the user' do
        before do
          stub_feature_flags(dap_impact_v1: user)
        end

        it { is_expected.to be(true) }
      end

      context 'when the flag is disabled' do
        before do
          stub_feature_flags(dap_impact_v1: false)
        end

        it { is_expected.to be(false) }
      end

      context 'when the dashboard declares an unknown feature token' do
        let(:config) { { 'title' => 'Test', 'constraints' => { 'feature_flag' => 'nope' } } }

        it 'raises in development so the typo cannot silently pass' do
          expect { satisfied }.to raise_error(ArgumentError, /Unknown feature_flag constraint/)
        end

        context 'in production' do
          before do
            allow(::Gitlab).to receive(:dev_or_test_env?).and_return(false)
          end

          it { is_expected.to be(false) }
        end
      end

      # The flag resolves per user, so two users can get different answers for the
      # same dashboard. This is what stops the policy condition being subject-scoped.
      context 'when the flag is enabled for another user only' do
        let_it_be(:other_user) { create(:user) }

        before do
          stub_feature_flags(dap_impact_v1: other_user)
        end

        it { is_expected.to be(false) }

        it 'is satisfied for the enabled user' do
          expect(described_class.satisfied?(dashboard, other_user)).to be(true)
        end

        it 'does not query group membership while no group has the flag' do
          expect(user).not_to receive(:authorized_groups)

          satisfied
        end
      end

      context 'when the flag is enabled for a root group' do
        let_it_be(:root_group) { create(:group) }
        let_it_be(:subgroup) { create(:group, parent: root_group) }
        let_it_be(:project) { create(:project, group: subgroup) }
        let_it_be(:other_root_group) { create(:group) }

        before do
          stub_feature_flags(dap_impact_v1: root_group)
        end

        it { is_expected.to be(false) }

        it 'is not satisfied for anonymous users' do
          expect(described_class.satisfied?(dashboard, nil)).to be(false)
        end

        it 'is not satisfied for a member of another root group only' do
          expect(described_class.satisfied?(dashboard, create(:user, reporter_of: other_root_group))).to be(false)
        end

        where(membership: [:root_group, :subgroup, :project])

        with_them do
          let(:member) { create(:user, reporter_of: public_send(membership)) }

          it 'is satisfied for a member anywhere in the hierarchy' do
            expect(described_class.satisfied?(dashboard, member)).to be(true)
          end
        end

        it 'does not query once per root group the user belongs to' do
          member = create(:user, reporter_of: other_root_group)
          # Warms the flag's gate cache, so the control counts only per-call queries.
          described_class.satisfied?(dashboard, member)
          control = ActiveRecord::QueryRecorder.new { described_class.satisfied?(dashboard, member) }

          create_list(:group, 2).each { |group| group.add_reporter(member) }

          expect { described_class.satisfied?(dashboard, member) }.not_to exceed_query_limit(control)
        end
      end

      context 'when the flag is enabled for a subgroup only' do
        let_it_be(:subgroup) { create(:group, parent: create(:group)) }

        before do
          stub_feature_flags(dap_impact_v1: subgroup)
        end

        it 'is not satisfied because only root groups are actors' do
          expect(described_class.satisfied?(dashboard, create(:user, reporter_of: subgroup))).to be(false)
        end
      end

      context 'when the flag is enabled for the user and a root group the user is not in' do
        before do
          stub_feature_flags(dap_impact_v1: [user, create(:group)])
        end

        it { is_expected.to be(true) }
      end
    end

    describe 'several kinds at once' do
      let(:config) do
        {
          'title' => 'Test',
          'constraints' => { 'license' => 'product_analytics', 'data' => ['clickhouse'] }
        }
      end

      before do
        stub_licensed_features(product_analytics: true)
        allow(::Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(clickhouse)
      end

      context 'when every kind is satisfied' do
        let(:clickhouse) { true }

        it { is_expected.to be(true) }
      end

      context 'when one kind is not satisfied' do
        let(:clickhouse) { false }

        it { is_expected.to be(false) }
      end
    end
  end

  # The schema decides what a dashboard may declare, these hashes decide what each
  # token does. A token in one but not the other validates, loads, and then raises
  # KeyError mid-request, which takes out the whole dashboard list rather than one
  # dashboard.
  describe 'agreement with the JSON schema' do
    let(:schema_constraints) do
      schema = ::Gitlab::Json::SafeParser.parse(
        File.read(Rails.root.join(Analytics::CustomDashboards::SystemDashboardsLoader::SCHEMA_PATH))
      )

      schema.dig('definitions', 'AnalyticsDashboard', 'properties', 'constraints', 'properties')
    end

    it 'knows every constraint kind the schema allows' do
      expect(described_class::KINDS).to match_array(schema_constraints.keys)
    end

    it 'has a predicate for every data source the schema allows' do
      expect(described_class::DATA_CHECKS.keys).to match_array(schema_constraints.dig('data', 'items', 'enum'))
    end

    it 'has a predicate for every feature flag the schema allows' do
      expect(described_class::FEATURE_FLAG_CHECKS.keys).to match_array(schema_constraints.dig('feature_flag', 'enum'))
    end

    it 'allows exactly the licence names the schema allows' do
      expect(described_class::LICENSED_FEATURES).to match_array(schema_constraints.dig('license', 'enum'))
    end

    it 'only allows licence names that are real licensed features' do
      names = schema_constraints.dig('license', 'enum').map(&:to_sym)

      expect(::GitlabSubscriptions::Features::ALL_FEATURES).to include(*names)
    end
  end
end
