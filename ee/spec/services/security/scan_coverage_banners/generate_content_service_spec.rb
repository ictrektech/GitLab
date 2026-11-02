# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanCoverageBanners::GenerateContentService, feature_category: :security_asset_inventories do
  let_it_be(:group) { create(:group) }
  let_it_be(:project1) { create(:project, namespace: group) }
  let_it_be(:project2) { create(:project, namespace: group) }

  subject(:result) { described_class.new(group).execute }

  context 'when the group has no projects' do
    let_it_be(:empty_group) { create(:group) }

    subject(:result) { described_class.new(empty_group).execute }

    it 'returns a successful response with a nil payload, not an error', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload).to be_nil
    end
  end

  context 'when all projects in the group are archived' do
    let_it_be(:archived_group) { create(:group) }
    let_it_be(:archived_project1) { create(:project, :archived, namespace: archived_group) }
    let_it_be(:archived_project2) { create(:project, :archived, namespace: archived_group) }

    subject(:result) { described_class.new(archived_group).execute }

    it 'returns the same nil payload as an empty group', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload).to be_nil
    end
  end

  context 'when no scanners are configured (state 1)' do
    it 'returns the warning variant with the no-scanners copy', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload[:variant]).to eq('warning')
      expect(result.payload[:title]).to eq(
        s_('ScanCoverageBanner|None of your active projects are scanned for security issues')
      )
      expect(result.payload[:message]).to eq(
        format(
          s_('ScanCoverageBanner|None of your %{active} projects are covered by application security testing. ' \
            'Set up scanning once to cover them all.'),
          active: '2'
        )
      )
      expect(result.payload[:cta_text]).to eq(s_('ScanCoverageBanner|Apply recommended profile'))
      expect(result.payload[:cta_url]).to eq(
        "/groups/#{group.full_path}/-/security/configuration#/enable_scanners/approach"
      )
      expect(result.payload[:banner_type]).to eq('no_scanners')
    end
  end

  context 'when a scan type has a row but it is entirely not_configured' do
    before do
      create(:analyzer_namespace_status, namespace: group, analyzer_type: :sast, success: 0, failure: 0, stale: 0)
    end

    it 'treats it the same as a missing row (0 configured)' do
      expect(result.payload[:variant]).to eq('warning')
    end
  end

  context 'when one scanner is configured at or above the 25% rollout threshold (state 2)' do
    before do
      create(:analyzer_namespace_status, namespace: group, analyzer_type: :sast, success: 1, failure: 0, stale: 0)
    end

    it 'returns the tip variant recommending secret detection', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload[:variant]).to eq('tip')
      expect(result.payload[:title]).to eq(
        s_('ScanCoverageBanner|Your projects check code, but not for leaked secrets')
      )
      expect(result.payload[:message]).to eq(
        format(
          s_('ScanCoverageBanner|%{count} of %{total} projects run application security testing. Add secret ' \
            "detection to the same projects to catch passwords and keys before they're merged."),
          count: '1', total: '2'
        )
      )
      expect(result.payload[:cta_text]).to eq(s_('ScanCoverageBanner|Add secret detection'))
      expect(result.payload[:cta_url]).to eq(
        "/groups/#{group.full_path}/-/security/configuration#/enable_scanners/approach"
      )
      expect(result.payload[:banner_type]).to eq('single_scanner_high')
    end
  end

  context 'when secret detection is configured instead, recommending SAST (state 2)' do
    before do
      create(:analyzer_namespace_status, namespace: group, analyzer_type: :secret_detection, success: 1, failure: 1,
        stale: 0)
    end

    it 'recommends application security testing with the secret-detection-specific copy', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload[:title]).to eq(
        s_('ScanCoverageBanner|Your projects check for leaked secrets, but not the code itself')
      )
      expect(result.payload[:message]).to eq(
        format(
          s_('ScanCoverageBanner|%{count} of %{total} projects scan for secrets. Add application security ' \
            "testing to the same projects to catch vulnerabilities before they're merged."),
          count: '2', total: '2'
        )
      )
      expect(result.payload[:cta_text]).to eq(s_('ScanCoverageBanner|Add application security testing'))
    end
  end

  context 'when a 1-project group has 1 scanner configured on it (100%, state 2)' do
    let_it_be(:small_group) { create(:group) }
    let_it_be(:small_project) { create(:project, namespace: small_group) }

    before do
      create(:analyzer_namespace_status, namespace: small_group, analyzer_type: :sast, success: 1, failure: 0,
        stale: 0)
    end

    subject(:result) { described_class.new(small_group).execute }

    it 'still returns state 2, not the threshold-met nil payload', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload[:variant]).to eq('tip')
      expect(result.payload[:title]).to eq(
        s_('ScanCoverageBanner|Your projects check code, but not for leaked secrets')
      )
    end
  end

  context 'when one scanner is configured below the 25% rollout threshold (state 3)' do
    let_it_be(:large_group) { create(:group) }

    before do
      create(:analyzer_namespace_status, namespace: large_group, analyzer_type: :sast, success: 10, failure: 0,
        stale: 0)
      allow(large_group).to receive(:all_unarchived_project_ids).and_return(Array.new(200) { |i| i + 1 })
    end

    subject(:result) { described_class.new(large_group).execute }

    it 'returns the "already set it up" copy, not state 2', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload[:variant]).to eq('tip')
      expect(result.payload[:title]).to eq(
        format(
          s_('ScanCoverageBanner|%{scanner} runs on %{count} of your %{total} projects'),
          scanner: 'Application security testing', count: '10', total: '200'
        )
      )
      expect(result.payload[:message]).to eq(
        format(
          s_("ScanCoverageBanner|You've already set it up. Add it to the other %{remaining} projects to cover " \
            'the whole group.'),
          remaining: '190'
        )
      )
      expect(result.payload[:cta_text]).to eq(
        format(
          s_('ScanCoverageBanner|Add %{scanner} to more projects'),
          scanner: 'application security testing'
        )
      )
      expect(result.payload[:cta_url]).to eq(
        "/groups/#{large_group.full_path}/-/security/configuration#/enable_scanners/approach"
      )
      expect(result.payload[:banner_type]).to eq('single_scanner_low')
    end
  end

  context 'when a scanner raw count exceeds the live project total (drift)' do
    let_it_be(:drifted_group) { create(:group) }

    before do
      create(:analyzer_namespace_status, namespace: drifted_group, analyzer_type: :sast, success: 130, failure: 0,
        stale: 0)
      allow(drifted_group).to receive(:all_unarchived_project_ids).and_return(Array.new(120) { |i| i + 1 })
    end

    subject(:result) { described_class.new(drifted_group).execute }

    it 'clamps the count so it never exceeds the project total, instead of the uncapped 130', :aggregate_failures do
      expect(result.payload[:title]).to eq(
        s_('ScanCoverageBanner|Your projects check code, but not for leaked secrets')
      )
      expect(result.payload[:message]).to include('120 of 120 projects')
      expect(result.payload[:message]).not_to include('130')
    end
  end

  context 'when 49 of 200 projects rounds to 25% but the raw fraction is 24.5% (boundary)' do
    let_it_be(:large_group) { create(:group) }

    before do
      create(:analyzer_namespace_status, namespace: large_group, analyzer_type: :sast, success: 49, failure: 0,
        stale: 0)
      allow(large_group).to receive(:all_unarchived_project_ids).and_return(Array.new(200) { |i| i + 1 })
    end

    subject(:result) { described_class.new(large_group).execute }

    it 'treats it as under-threshold (state 3), not above-threshold (state 2)' do
      expect(result.payload[:banner_type]).to eq('single_scanner_low')
    end

    context 'and a second scanner is also configured but under threshold' do
      before do
        create(:analyzer_namespace_status, namespace: large_group, analyzer_type: :secret_detection, success: 1,
          failure: 0, stale: 0)
      end

      it 'returns state 4 instead of the threshold-met nil payload', :aggregate_failures do
        expect(result).to be_success
        expect(result.payload).not_to be_nil
        expect(result.payload[:title]).to eq(
          s_('ScanCoverageBanner|Security scanning runs on some projects, not most')
        )
      end
    end
  end

  context 'when the raw fraction is exactly 25% (50 of 200, boundary)' do
    let_it_be(:large_group) { create(:group) }

    before do
      create(:analyzer_namespace_status, namespace: large_group, analyzer_type: :sast, success: 50, failure: 0,
        stale: 0)
      allow(large_group).to receive(:all_unarchived_project_ids).and_return(Array.new(200) { |i| i + 1 })
    end

    subject(:result) { described_class.new(large_group).execute }

    it 'treats exactly 25% as above-threshold (state 2), using >= not >', :aggregate_failures do
      expect(result.payload[:banner_type]).to eq('single_scanner_high')
      expect(result.payload[:message]).to include('50 of 200 projects')
    end

    context 'and secret detection is also configured, also at exactly 25%' do
      before do
        create(:analyzer_namespace_status, namespace: large_group, analyzer_type: :secret_detection, success: 50,
          failure: 0, stale: 0)
      end

      it 'treats the threshold as met and returns a nil payload', :aggregate_failures do
        expect(result).to be_success
        expect(result.payload).to be_nil
      end
    end

    context 'and secret detection is also configured, but below threshold (only one of the two is above)' do
      before do
        create(:analyzer_namespace_status, namespace: large_group, analyzer_type: :secret_detection, success: 1,
          failure: 0, stale: 0)
      end

      it 'treats the threshold as met because at least one scanner qualifies, not requiring both',
        :aggregate_failures do
        expect(result).to be_success
        expect(result.payload).to be_nil
      end
    end
  end

  context 'when SAST is below threshold and secret detection is above it (mirrored asymmetric case)' do
    let_it_be(:large_group) { create(:group) }

    before do
      create(:analyzer_namespace_status, namespace: large_group, analyzer_type: :sast, success: 1, failure: 0,
        stale: 0)
      create(:analyzer_namespace_status, namespace: large_group, analyzer_type: :secret_detection, success: 50,
        failure: 0, stale: 0)
      allow(large_group).to receive(:all_unarchived_project_ids).and_return(Array.new(200) { |i| i + 1 })
    end

    subject(:result) { described_class.new(large_group).execute }

    it 'treats the threshold as met regardless of which scanner qualifies', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload).to be_nil
    end
  end

  context 'when two scanners are configured, neither above the rollout threshold (state 4)' do
    let_it_be(:large_group) { create(:group) }

    before do
      create(:analyzer_namespace_status, namespace: large_group, analyzer_type: :sast, success: 10, failure: 0,
        stale: 0)
      create(:analyzer_namespace_status, namespace: large_group, analyzer_type: :secret_detection, success: 20,
        failure: 0, stale: 0)
      allow(large_group).to receive(:all_unarchived_project_ids).and_return(Array.new(8567) { |i| i + 1 })
    end

    subject(:result) { described_class.new(large_group).execute }

    it 'lists application security testing first, then secret detection, with delimited counts',
      :aggregate_failures do
      expect(result).to be_success
      expect(result.payload[:variant]).to eq('tip')
      expect(result.payload[:title]).to eq(
        s_('ScanCoverageBanner|Security scanning runs on some projects, not most')
      )
      expect(result.payload[:message]).to eq(
        format(
          s_('ScanCoverageBanner|%{scanner_a} covers %{count_a} of %{total} projects and %{scanner_b} covers ' \
            '%{count_b}. Bring every project in the group up to the same coverage.'),
          scanner_a: 'Application security testing', count_a: '10',
          scanner_b: 'secret detection', count_b: '20', total: '8,567'
        )
      )
      expect(result.payload[:cta_text]).to eq(s_('ScanCoverageBanner|Apply recommended profile'))
      expect(result.payload[:cta_url]).to eq(
        "/groups/#{large_group.full_path}/-/security/configuration#/enable_scanners/approach"
      )
      expect(result.payload[:banner_type]).to eq('two_scanners')
    end
  end

  context 'when the rollout threshold has been met (state 5)' do
    before do
      create(:analyzer_namespace_status, namespace: group, analyzer_type: :sast, success: 2, failure: 0, stale: 0)
      create(:analyzer_namespace_status, namespace: group, analyzer_type: :secret_detection, success: 1, failure: 0,
        stale: 0)
    end

    it 'returns a successful response with a nil payload, not an error', :aggregate_failures do
      expect(result).to be_success
      expect(result.payload).to be_nil
    end
  end

  context 'when the total is large enough to need a thousands separator' do
    let_it_be(:huge_group) { create(:group) }

    before do
      allow(huge_group).to receive(:all_unarchived_project_ids).and_return(Array.new(6814) { |i| i + 1 })
    end

    subject(:result) { described_class.new(huge_group).execute }

    it 'formats the total with a thousands separator' do
      expect(result.payload[:message]).to include('6,814')
    end
  end
end
