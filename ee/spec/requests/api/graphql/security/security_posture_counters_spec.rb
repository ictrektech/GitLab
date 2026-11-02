# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.group.securityPostureCounters', feature_category: :security_asset_inventories do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project1) { create(:project, namespace: group) }
  let_it_be(:project2) { create(:project, namespace: group) }
  let_it_be(:project3) { create(:project, namespace: subgroup) }

  let(:query) do
    <<~GQL
      query($fullPath: ID!) {
        group(fullPath: $fullPath) {
          securityPostureCounters {
            total
            withScanners
            withFailures
            withStale
            withTriageCoverage
          }
        }
      }
    GQL
  end

  let(:variables) { { fullPath: group.full_path } }
  let(:counters_data) { graphql_data_at(:group, :security_posture_counters) }

  subject(:execute_query) { post_graphql(query, current_user: current_user, variables: variables) }

  before do
    stub_licensed_features(security_inventory: true, security_scan_profiles: true)
  end

  context 'when the user does not have permission' do
    it 'returns null for the field' do
      execute_query

      expect(graphql_errors).to be_nil
      expect(counters_data).to be_nil
    end
  end

  context 'when the user has permission' do
    before_all do
      group.add_developer(current_user)
    end

    context 'when there are no inventory filters' do
      it 'returns the unarchived project count as total and zero for the posture counters' do
        execute_query

        expect(graphql_errors).to be_nil
        expect(counters_data).to eq(
          'total' => 3,
          'withScanners' => 0,
          'withFailures' => 0,
          'withStale' => 0,
          'withTriageCoverage' => 0
        )
      end
    end

    context 'when a project has a triage and remediation trigger enabled' do
      let_it_be(:filter_with_triage_coverage) do
        create(:security_inventory_filters, project: project1,
          triage_capabilities: { sast_false_positive: [true, false] })
      end

      context 'when the security_scan_profiles license is available' do
        before do
          stub_licensed_features(security_inventory: true, security_scan_profiles: true)
        end

        it 'counts it towards withTriageCoverage' do
          execute_query

          expect(graphql_errors).to be_nil
          expect(counters_data['withTriageCoverage']).to eq(1)
        end

        context 'when the user can read the security inventory but not security scan profiles' do
          let_it_be(:member_role) do
            create(:member_role, :guest, :read_vulnerability, :admin_vulnerability, namespace: group)
          end

          let_it_be(:custom_role_user) { create(:user) }

          let(:current_user) { custom_role_user }

          before_all do
            create(:group_member, :guest, user: custom_role_user, source: group, member_role: member_role)
          end

          before do
            stub_licensed_features(security_inventory: true, security_scan_profiles: true, custom_roles: true)
          end

          it 'returns null for withTriageCoverage' do
            execute_query

            expect(graphql_errors).to be_nil
            expect(counters_data).to include('total' => 3, 'withTriageCoverage' => nil)
          end
        end

        context 'when the user is an auditor' do
          let_it_be(:auditor) { create(:user, :auditor) }

          let(:current_user) { auditor }

          it 'counts it towards withTriageCoverage' do
            execute_query

            expect(graphql_errors).to be_nil
            expect(counters_data['withTriageCoverage']).to eq(1)
          end
        end
      end

      context 'when the security_scan_profiles license is unavailable' do
        before do
          stub_licensed_features(security_inventory: true, security_scan_profiles: false)
        end

        it 'returns null for withTriageCoverage instead of erroring' do
          execute_query

          expect(graphql_errors).to be_nil
          expect(counters_data['withTriageCoverage']).to be_nil
        end
      end
    end

    context 'when inventory filters exist' do
      let_it_be(:filter1) do
        create(:security_inventory_filters, project: project1,
          has_scanners: true, has_failed_or_warning: true, has_stale: false)
      end

      let_it_be(:filter2) do
        create(:security_inventory_filters, project: project2,
          has_scanners: true, has_failed_or_warning: false, has_stale: true)
      end

      let_it_be(:filter3) do
        create(:security_inventory_filters, project: project3,
          has_scanners: false, has_failed_or_warning: false, has_stale: false)
      end

      it 'returns correct aggregate counts' do
        execute_query

        expect(graphql_errors).to be_nil
        expect(counters_data).to eq(
          'total' => 3,
          'withScanners' => 2,
          'withFailures' => 1,
          'withStale' => 1,
          'withTriageCoverage' => 0
        )
      end

      context 'when some projects are archived' do
        let_it_be(:archived_project) { create(:project, :archived, namespace: group) }
        let_it_be(:archived_filter) do
          create(:security_inventory_filters, :archived_project, project: archived_project,
            has_scanners: true, has_failed_or_warning: true, has_stale: true)
        end

        it 'excludes archived projects from all counts' do
          execute_query

          expect(graphql_errors).to be_nil
          expect(counters_data).to eq(
            'total' => 3,
            'withScanners' => 2,
            'withFailures' => 1,
            'withStale' => 1,
            'withTriageCoverage' => 0
          )
        end
      end
    end
  end
end
