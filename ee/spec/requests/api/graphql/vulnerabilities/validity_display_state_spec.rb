# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.vulnerability.validityDisplayState', feature_category: :secret_detection do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:project) { create(:project) }
  let_it_be_with_reload(:vulnerability) do
    create(:vulnerability, project: project, report_type: 'secret_detection')
  end

  let(:vuln_gid) { vulnerability.to_global_id.to_s }
  let(:query) do
    <<~GQL
      query($id: VulnerabilityID!) {
        vulnerability(id: $id) {
          validityDisplayState
        }
      }
    GQL
  end

  before_all do
    project.add_developer(user)
  end

  before do
    stub_licensed_features(security_dashboard: true, secret_detection_validity_checks: true)
    project.security_setting.update!(validity_checks_enabled: true)
  end

  subject(:post_query) do
    post_graphql(query, current_user: user, variables: { id: vuln_gid })
  end

  def display_state
    graphql_data.dig('vulnerability', 'validityDisplayState')
  end

  def create_gitleaks_finding(token_type, target_vulnerability = vulnerability, *traits, **opts)
    create(
      :vulnerabilities_finding,
      *traits,
      vulnerability: target_vulnerability,
      report_type: :secret_detection,
      raw_metadata: {
        identifiers: [{ type: 'gitleaks_rule_id', value: token_type, name: token_type }]
      }.to_json,
      **opts
    )
  end

  context 'when the display gates fail' do
    shared_examples 'returns no display state' do
      it 'has a nil validityDisplayState' do
        post_query

        expect(display_state).to be_nil
      end
    end

    context 'when report_type is not secret_detection' do
      before do
        vulnerability.update!(report_type: 'sast')
      end

      it_behaves_like 'returns no display state'
    end

    # These three gates sit after the finding check in should_display?, so each
    # needs a finding to reach the gate it is exercising.
    context 'when secret_detection_validity_checks is not licensed' do
      before do
        create_gitleaks_finding('AWS')
        stub_licensed_features(security_dashboard: true, secret_detection_validity_checks: false)
      end

      it_behaves_like 'returns no display state'
    end

    context 'when validity_checks_enabled is false' do
      before do
        create_gitleaks_finding('AWS')
        project.security_setting.update!(validity_checks_enabled: false)
      end

      it_behaves_like 'returns no display state'
    end

    context 'when the project has no security setting' do
      before do
        create_gitleaks_finding('AWS')
        project.security_setting.destroy!
      end

      it_behaves_like 'returns no display state'
    end

    context 'when the vulnerability has no finding' do
      it_behaves_like 'returns no display state'
    end
  end

  context 'with a token type supported for the detecting analyzer' do
    it 'returns PENDING_VERIFICATION when no status row exists' do
      create_gitleaks_finding('AWS')
      post_query

      expect(display_state).to eq('PENDING_VERIFICATION')
    end

    it 'returns the stored status when a row exists' do
      create_gitleaks_finding('AWS', vulnerability, :with_token_status, token_status: :active)
      post_query

      expect(display_state).to eq('ACTIVE')
    end
  end

  context 'with a token type supported only for the other analyzer' do
    # A status row left over from before scheduling was restricted must not
    # show as a verdict.
    it 'returns NOT_CHECKED_BY_ANALYZER and ignores a leftover status row' do
      create_gitleaks_finding('OpenAiProjectKey', vulnerability, :with_token_status, token_status: :inactive)
      post_query

      expect(display_state).to eq('NOT_CHECKED_BY_ANALYZER')
    end
  end

  context 'with a token type in no registry' do
    it 'returns NO_VENDOR_SUPPORT' do
      create_gitleaks_finding('no_such_vendor_token')
      post_query

      expect(display_state).to eq('NO_VENDOR_SUPPORT')
    end
  end

  describe 'project.vulnerabilities list' do
    let_it_be(:second_user) { create(:user) }

    let(:list_query) do
      <<~GQL
        query {
          project(fullPath: "#{project.full_path}") {
            vulnerabilities(reportType: [SECRET_DETECTION]) {
              nodes {
                validityDisplayState
              }
            }
          }
        }
      GQL
    end

    def create_vulnerability_with_finding(token_type, *traits, **opts)
      vuln = create(:vulnerability, project: project, report_type: 'secret_detection')
      create_gitleaks_finding(token_type, vuln, *traits, **opts)
      vuln
    end

    before_all do
      project.add_developer(second_user)
    end

    it 'returns a display state per vulnerability without additional queries per record' do
      create_vulnerability_with_finding('AWS', :with_token_status, token_status: :active)
      create_vulnerability_with_finding('no_such_vendor_token')

      # First-ever request of a user writes sign-in tracking and preferences;
      # warm both users so the control only measures the query itself.
      post_graphql(list_query, current_user: user)
      post_graphql(list_query, current_user: second_user)

      control = ActiveRecord::QueryRecorder.new { post_graphql(list_query, current_user: user) }

      create_vulnerability_with_finding('AWS')
      create_vulnerability_with_finding('OpenAiProjectKey', :with_token_status, token_status: :inactive)
      create_vulnerability_with_finding('no_such_vendor_token')

      expect { post_graphql(list_query, current_user: second_user) }.not_to exceed_query_limit(control)

      states = graphql_data.dig('project', 'vulnerabilities', 'nodes').pluck('validityDisplayState')
      expect(states).to match_array(%w[
        ACTIVE
        NO_VENDOR_SUPPORT
        PENDING_VERIFICATION
        NOT_CHECKED_BY_ANALYZER
        NO_VENDOR_SUPPORT
      ])
    end
  end
end
