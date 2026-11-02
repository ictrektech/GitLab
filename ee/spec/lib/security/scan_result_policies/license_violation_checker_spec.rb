# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::LicenseViolationChecker, feature_category: :security_policy_management do
  let_it_be(:project) { create(:project) }

  let(:case5) do
    [
      ['GPL v3', 'GNU 3', 'A'],
      ['MIT', 'MIT License', 'B'],
      ['GPL v3', 'GNU 3', 'C'],
      ['Apache 2', 'Apache License 2', 'D']
    ]
  end

  let(:case4) { [['GPL v3', 'GNU 3', 'A'], ['MIT', 'MIT License', 'B'], ['GPL v3', 'GNU 3', 'C']] }
  let(:case3) { [['GPL v3', 'GNU 3', 'A'], ['MIT', 'MIT License', 'B']] }
  let(:case2) { [['GPL v3', 'GNU 3', 'A']] }
  let(:case1) { [] }

  let(:license_name_spdx_map) { { 'GNU 3' => 'GPL v3', 'MIT License' => 'MIT' } }

  describe 'possible combinations' do
    using RSpec::Parameterized::TableSyntax

    let(:violation1) { { 'GNU 3' => %w[A] } }
    let(:violation2) { { 'GNU 3' => %w[A C] } }
    let(:violation3) { { 'GNU 3' => %w[C] } }
    let(:violation4) { { 'Apache License 2' => %w[D] } }

    subject(:service) { described_class.new(project, pipeline_report, target_branch_report) }

    context 'with software_licenses' do
      include_context 'for license_checker'

      with_them do
        let_it_be(:target_branch_report) { create(:ci_reports_license_scanning_report) }
        let_it_be(:pipeline_report) { create(:ci_reports_license_scanning_report) }

        let(:match_on_inclusion_license) { policy_state == :denied }
        let(:license_states) { states }
        let(:license_name) { policy_license[1] }
        let(:scan_result_policy_read) do
          create(:scan_result_policy_read, project: project, license_states: license_states,
            match_on_inclusion_license: match_on_inclusion_license)
        end

        let(:approval_policy_source) do
          Security::ApprovalPolicySource.new(
            project: project, action_idx: 0, scan_result_policy_read: scan_result_policy_read
          )
        end

        before do
          target_branch.each do |ld|
            target_branch_report.add_license(id: ld[0], name: ld[1]).add_dependency(name: ld[2])
          end

          pipeline_branch.each do |ld|
            pipeline_report.add_license(id: ld[0], name: ld[1]).add_dependency(name: ld[2])
          end

          create(:software_license_policy, policy_state,
            project: project,
            scan_result_policy_read: scan_result_policy_read,
            software_license_spdx_identifier: license_name_spdx_map[license_name]
          )
        end

        it 'syncs approvals_required' do
          result = service.execute(approval_policy_source)

          expect(result).to eq(violated_licenses)
        end
      end
    end

    context 'with custom_software_licenses' do
      include_context 'for license_checker'

      with_them do
        let_it_be(:target_branch_report) { create(:ci_reports_license_scanning_report) }
        let_it_be(:pipeline_report) { create(:ci_reports_license_scanning_report) }

        let(:match_on_inclusion_license) { policy_state == :denied }
        let(:license_states) { states }

        let(:custom_license) { create(:custom_software_license, name: policy_license[1]) }
        let(:scan_result_policy_read) do
          create(:scan_result_policy_read, project: project, license_states: license_states,
            match_on_inclusion_license: match_on_inclusion_license)
        end

        let(:approval_policy_source) do
          Security::ApprovalPolicySource.new(
            project: project, action_idx: 0, scan_result_policy_read: scan_result_policy_read
          )
        end

        before do
          target_branch.each do |ld|
            target_branch_report.add_license(id: ld[0], name: ld[1]).add_dependency(name: ld[2])
          end

          pipeline_branch.each do |ld|
            pipeline_report.add_license(id: ld[0], name: ld[1]).add_dependency(name: ld[2])
          end

          create(:software_license_policy, policy_state,
            project: project,
            custom_software_license: custom_license,
            software_license_spdx_identifier: nil,
            scan_result_policy_read: scan_result_policy_read
          )
        end

        subject(:service_result) { service.execute(approval_policy_source) }

        it 'syncs approvals_required' do
          expect(service_result).to eq(violated_licenses)
        end
      end

      context 'with software licenses and custom_software_licenses' do
        include_context 'for license_checker'

        with_them do
          let_it_be(:target_branch_report) { create(:ci_reports_license_scanning_report) }
          let_it_be(:pipeline_report) { create(:ci_reports_license_scanning_report) }

          let(:match_on_inclusion_license) { policy_state == :denied }
          let(:license_states) { states }

          let(:catalog_license?) { policy_license[0].present? }

          let(:scan_result_policy_read) do
            create(:scan_result_policy_read, project: project, license_states: license_states,
              match_on_inclusion_license: match_on_inclusion_license)
          end

          let(:approval_policy_source) do
            Security::ApprovalPolicySource.new(
              project: project, action_idx: 0, scan_result_policy_read: scan_result_policy_read
            )
          end

          before do
            target_branch.each do |ld|
              target_branch_report.add_license(id: ld[0], name: ld[1]).add_dependency(name: ld[2])
            end

            pipeline_branch.each do |ld|
              pipeline_report.add_license(id: ld[0], name: ld[1]).add_dependency(name: ld[2])
            end

            if catalog_license?
              create(:software_license_policy, policy_state,
                project: project,
                custom_software_license: nil,
                scan_result_policy_read: scan_result_policy_read,
                software_license_spdx_identifier: policy_license[0]
              )
            else
              create(:software_license_policy, policy_state,
                project: project,
                custom_software_license: create(:custom_software_license, name: policy_license[1]),
                software_license_spdx_identifier: nil,
                scan_result_policy_read: scan_result_policy_read
              )
            end
          end

          it 'syncs approvals_required' do
            result = service.execute(approval_policy_source)

            expect(result).to eq(violated_licenses)
          end
        end
      end
    end

    context 'when backed by approval_policy_rule' do
      let_it_be(:target_branch_report) { create(:ci_reports_license_scanning_report) }
      let_it_be(:pipeline_report) { create(:ci_reports_license_scanning_report) }

      let(:approval_policy_rule) do
        create(:approval_policy_rule, :license_finding,
          content: {
            'type' => 'license_finding',
            'branches' => [],
            'match_on_inclusion_license' => true,
            'license_types' => ['GPL v3'],
            'license_states' => %w[detected]
          })
      end

      let(:scan_result_policy_read) do
        create(:scan_result_policy_read, project: project,
          license_states: %w[detected], match_on_inclusion_license: true,
          approval_policy_rule: approval_policy_rule)
      end

      let(:approval_policy_source) do
        Security::ApprovalPolicySource.new(
          project: project,
          action_idx: 0,
          scan_result_policy_read: scan_result_policy_read,
          approval_policy_rule: approval_policy_rule
        )
      end

      subject(:service) { described_class.new(project, pipeline_report, target_branch_report) }

      before do
        target_branch_report.add_license(id: 'GPL v3', name: 'GNU 3').add_dependency(name: 'A')

        create(:software_license_policy, :denied,
          project: project,
          approval_policy_rule: approval_policy_rule,
          scan_result_policy_read: scan_result_policy_read,
          software_license_spdx_identifier: 'GPL v3')
      end

      it 'queries by approval_policy_rule_id' do
        result = service.execute(approval_policy_source)

        expect(result).to eq({ 'GNU 3' => ['A'] })
      end
    end

    context 'when backed by approval_policy_rule with custom_software_license' do
      let_it_be(:target_branch_report) { create(:ci_reports_license_scanning_report) }
      let_it_be(:pipeline_report) { create(:ci_reports_license_scanning_report) }

      let(:approval_policy_rule) do
        create(:approval_policy_rule, :license_finding,
          content: {
            'type' => 'license_finding',
            'branches' => [],
            'match_on_inclusion_license' => true,
            'license_types' => ['Custom License'],
            'license_states' => %w[detected]
          })
      end

      let(:scan_result_policy_read) do
        create(:scan_result_policy_read, project: project,
          license_states: %w[detected], match_on_inclusion_license: true,
          approval_policy_rule: approval_policy_rule)
      end

      let(:approval_policy_source) do
        Security::ApprovalPolicySource.new(
          project: project,
          action_idx: 0,
          scan_result_policy_read: scan_result_policy_read,
          approval_policy_rule: approval_policy_rule
        )
      end

      subject(:service) { described_class.new(project, pipeline_report, target_branch_report) }

      before do
        target_branch_report.add_license(id: nil, name: 'Custom License').add_dependency(name: 'A')

        create(:software_license_policy, :denied,
          project: project,
          approval_policy_rule: approval_policy_rule,
          scan_result_policy_read: scan_result_policy_read,
          custom_software_license: create(:custom_software_license, name: 'Custom License'),
          software_license_spdx_identifier: nil)
      end

      it 'queries by approval_policy_rule_id' do
        result = service.execute(approval_policy_source)

        expect(result).to eq({ 'Custom License' => ['A'] })
      end
    end

    context 'when backed by approval_policy_rule with software and custom_software_licenses' do
      let_it_be(:target_branch_report) { create(:ci_reports_license_scanning_report) }
      let_it_be(:pipeline_report) { create(:ci_reports_license_scanning_report) }

      let(:approval_policy_rule) do
        create(:approval_policy_rule, :license_finding,
          content: {
            'type' => 'license_finding',
            'branches' => [],
            'match_on_inclusion_license' => true,
            'license_types' => ['GPL v3', 'Custom License'],
            'license_states' => %w[detected]
          })
      end

      let(:scan_result_policy_read) do
        create(:scan_result_policy_read, project: project,
          license_states: %w[detected], match_on_inclusion_license: true,
          approval_policy_rule: approval_policy_rule)
      end

      let(:approval_policy_source) do
        Security::ApprovalPolicySource.new(
          project: project,
          action_idx: 0,
          scan_result_policy_read: scan_result_policy_read,
          approval_policy_rule: approval_policy_rule
        )
      end

      subject(:service) { described_class.new(project, pipeline_report, target_branch_report) }

      before do
        target_branch_report.add_license(id: 'GPL v3', name: 'GNU 3').add_dependency(name: 'A')
        target_branch_report.add_license(id: nil, name: 'Custom License').add_dependency(name: 'B')

        create(:software_license_policy, :denied,
          project: project,
          approval_policy_rule: approval_policy_rule,
          scan_result_policy_read: scan_result_policy_read,
          software_license_spdx_identifier: 'GPL v3')

        create(:software_license_policy, :denied,
          project: project,
          approval_policy_rule: approval_policy_rule,
          scan_result_policy_read: scan_result_policy_read,
          custom_software_license: create(:custom_software_license, name: 'Custom License'),
          software_license_spdx_identifier: nil)
      end

      it 'queries by approval_policy_rule_id' do
        result = service.execute(approval_policy_source)

        expect(result).to eq({ 'GNU 3' => ['A'], 'Custom License' => ['B'] })
      end
    end
  end

  describe '::MULTI_LICENSE_NODE_TYPES' do
    it 'excludes :plus, since it is a single license, not a genuine multi-license expression' do
      expect(described_class::MULTI_LICENSE_NODE_TYPES).to eq(%i[and or with])
    end
  end

  describe 'compound SPDX expressions under license_types' do
    let(:target_branch_report) { create(:ci_reports_license_scanning_report) }
    let(:pipeline_report) { create(:ci_reports_license_scanning_report) }

    let(:match_on_inclusion_license) { false }

    let(:scan_result_policy_read) do
      create(:scan_result_policy_read, project: project, license_states: %w[detected],
        match_on_inclusion_license: match_on_inclusion_license)
    end

    let(:approval_policy_source) do
      Security::ApprovalPolicySource.new(
        project: project, action_idx: 0, scan_result_policy_read: scan_result_policy_read
      )
    end

    subject(:service) { described_class.new(project, pipeline_report, target_branch_report) }

    before do
      target_branch_report.add_license(id: nil, name: 'MIT AND Apache-2.0').add_dependency(name: 'A')
    end

    context 'when the policy allows unknown licenses' do
      before do
        create(:software_license_policy, :allowed,
          project: project,
          custom_software_license: create(:custom_software_license, name: 'unknown'),
          software_license_spdx_identifier: nil,
          scan_result_policy_read: scan_result_policy_read)
      end

      it 'does not flag the expression as a violation' do
        expect(service.execute(approval_policy_source)).to be_nil
      end
    end

    context 'when the policy does not mention unknown licenses' do
      before do
        create(:software_license_policy, :allowed,
          project: project,
          software_license_spdx_identifier: 'MIT',
          scan_result_policy_read: scan_result_policy_read)
      end

      it 'denies the license, attributed by unknown rather than the raw expression' do
        result = service.execute(approval_policy_source)

        expect(result).to eq({ 'unknown' => ['A'] })
      end
    end

    context 'when the policy explicitly denies unknown licenses' do
      let(:match_on_inclusion_license) { true }

      before do
        create(:software_license_policy, :denied,
          project: project,
          custom_software_license: create(:custom_software_license, name: 'unknown'),
          software_license_spdx_identifier: nil,
          scan_result_policy_read: scan_result_policy_read)
      end

      it 'denies the license via the deny-list path, attributed by unknown' do
        result = service.execute(approval_policy_source)

        expect(result).to eq({ 'unknown' => ['A'] })
      end
    end

    context 'when the report also has a literal unknown license' do
      let(:match_on_inclusion_license) { true }

      before do
        target_branch_report.add_license(id: 'unknown', name: 'unknown').add_dependency(name: 'B')

        create(:software_license_policy, :denied,
          project: project,
          custom_software_license: create(:custom_software_license, name: 'unknown'),
          software_license_spdx_identifier: nil,
          scan_result_policy_read: scan_result_policy_read)
      end

      it 'merges both dependencies under the same unknown entry' do
        result = service.execute(approval_policy_source)

        expect(result).to eq({ 'unknown' => %w[A B] })
      end
    end

    context 'when the policy denies an unrelated license and never mentions unknown' do
      let(:match_on_inclusion_license) { true }

      before do
        target_branch_report.add_license(id: 'GPL-2.0', name: 'GPL-2.0').add_dependency(name: 'C')

        create(:software_license_policy, :denied,
          project: project,
          software_license_spdx_identifier: 'GPL-2.0',
          scan_result_policy_read: scan_result_policy_read)
      end

      it 'does not attribute the unrelated expression license' do
        result = service.execute(approval_policy_source)

        expect(result).to eq({ 'GPL-2.0' => ['C'] })
      end
    end

    context 'when the policy allows a custom license name equal to the raw expression text' do
      before do
        create(:software_license_policy, :allowed,
          project: project,
          custom_software_license: create(:custom_software_license, name: 'MIT AND Apache-2.0'),
          software_license_spdx_identifier: nil,
          scan_result_policy_read: scan_result_policy_read)
      end

      it 'does not match, so it is denied like any other unattended compound expression' do
        result = service.execute(approval_policy_source)

        expect(result).to eq({ 'unknown' => ['A'] })
      end
    end

    context 'when the policy denies a custom license name equal to the raw expression text' do
      let(:match_on_inclusion_license) { true }

      before do
        create(:software_license_policy, :denied,
          project: project,
          custom_software_license: create(:custom_software_license, name: 'MIT AND Apache-2.0'),
          software_license_spdx_identifier: nil,
          scan_result_policy_read: scan_result_policy_read)
      end

      it 'does not match, so the dependency is not denied by this rule' do
        expect(service.execute(approval_policy_source)).to be_nil
      end
    end

    context 'when the report has two distinct compound expressions and the policy names one by raw text' do
      let(:match_on_inclusion_license) { true }

      before do
        target_branch_report.add_license(id: nil, name: 'BSD-3-Clause AND ISC').add_dependency(name: 'E')

        create(:software_license_policy, :denied,
          project: project,
          custom_software_license: create(:custom_software_license, name: 'MIT AND Apache-2.0'),
          software_license_spdx_identifier: nil,
          scan_result_policy_read: scan_result_policy_read)
      end

      it 'denies neither, since a raw-text match on one never leaks tolerance to the other' do
        expect(service.execute(approval_policy_source)).to be_nil
      end
    end

    context 'when the report has two distinct compound expressions and the policy denies unknown' do
      let(:match_on_inclusion_license) { true }

      before do
        target_branch_report.add_license(id: nil, name: 'BSD-3-Clause AND ISC').add_dependency(name: 'E')

        create(:software_license_policy, :denied,
          project: project,
          custom_software_license: create(:custom_software_license, name: 'unknown'),
          software_license_spdx_identifier: nil,
          scan_result_policy_read: scan_result_policy_read)
      end

      it 'denies both, merged under the same unknown entry' do
        result = service.execute(approval_policy_source)

        expect(result).to eq({ 'unknown' => %w[E A] })
      end
    end

    context 'when two distinct compound expressions share a dependency name' do
      let(:match_on_inclusion_license) { true }

      before do
        target_branch_report.add_license(id: nil, name: 'BSD-3-Clause AND ISC').add_dependency(name: 'A')

        create(:software_license_policy, :denied,
          project: project,
          custom_software_license: create(:custom_software_license, name: 'unknown'),
          software_license_spdx_identifier: nil,
          scan_result_policy_read: scan_result_policy_read)
      end

      it 'does not duplicate the dependency name in the merged unknown entry' do
        result = service.execute(approval_policy_source)

        expect(result).to eq({ 'unknown' => ['A'] })
      end
    end

    context 'when the expression uses OR or WITH instead of AND' do
      using RSpec::Parameterized::TableSyntax

      where(:expression) do
        ['MIT OR Apache-2.0', 'GPL-2.0 WITH Classpath-exception-2.0']
      end

      before do
        target_branch_report.add_license(id: nil, name: expression).add_dependency(name: 'D')

        create(:software_license_policy, :allowed,
          project: project,
          custom_software_license: create(:custom_software_license, name: 'unknown'),
          software_license_spdx_identifier: nil,
          scan_result_policy_read: scan_result_policy_read)
      end

      with_them do
        it 'falls back to unknown the same way AND does' do
          expect(service.execute(approval_policy_source)).to be_nil
        end
      end
    end

    context 'when the fallback flag is disabled' do
      before do
        stub_feature_flags(license_types_unknown_expression_fallback: false)

        create(:software_license_policy, :allowed,
          project: project,
          custom_software_license: create(:custom_software_license, name: 'unknown'),
          software_license_spdx_identifier: nil,
          scan_result_policy_read: scan_result_policy_read)
      end

      it 'compares the raw expression literally, so allowing unknown does not help' do
        result = service.execute(approval_policy_source)

        expect(result).to eq({ 'MIT AND Apache-2.0' => ['A'] })
      end
    end
  end

  describe 'single plus-suffixed licenses under license_types' do
    let(:target_branch_report) { create(:ci_reports_license_scanning_report) }
    let(:pipeline_report) { create(:ci_reports_license_scanning_report) }

    let(:scan_result_policy_read) do
      create(:scan_result_policy_read, project: project, license_states: %w[detected],
        match_on_inclusion_license: false)
    end

    let(:approval_policy_source) do
      Security::ApprovalPolicySource.new(
        project: project, action_idx: 0, scan_result_policy_read: scan_result_policy_read
      )
    end

    subject(:service) { described_class.new(project, pipeline_report, target_branch_report) }

    before do
      target_branch_report.add_license(id: 'LGPL-2.0+', name: 'LGPL-2.0+').add_dependency(name: 'A')

      create(:software_license_policy, :allowed,
        project: project,
        custom_software_license: create(:custom_software_license, name: 'LGPL-2.0+'),
        software_license_spdx_identifier: nil,
        scan_result_policy_read: scan_result_policy_read)
    end

    it 'matches the license by its own identifier instead of falling back to unknown' do
      expect(service.execute(approval_policy_source)).to be_nil
    end
  end

  describe 'license_states newly_detected only, under license_types' do
    let(:target_branch_report) { create(:ci_reports_license_scanning_report) }
    let(:pipeline_report) { create(:ci_reports_license_scanning_report) }

    let(:scan_result_policy_read) do
      create(:scan_result_policy_read, project: project, license_states: ['newly_detected'],
        match_on_inclusion_license: false)
    end

    let(:approval_policy_source) do
      Security::ApprovalPolicySource.new(
        project: project, action_idx: 0, scan_result_policy_read: scan_result_policy_read
      )
    end

    subject(:service) { described_class.new(project, pipeline_report, target_branch_report) }

    before do
      pipeline_report.add_license(id: nil, name: 'MIT AND Apache-2.0').add_dependency(name: 'A')

      create(:software_license_policy, :allowed,
        project: project,
        custom_software_license: create(:custom_software_license, name: 'unknown'),
        software_license_spdx_identifier: nil,
        scan_result_policy_read: scan_result_policy_read)
    end

    it 'still falls back to unknown for the diff-based newly-detected branch' do
      expect(service.execute(approval_policy_source)).to be_nil
    end
  end
end
