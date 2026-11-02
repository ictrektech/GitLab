# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::SecurityUpdate::RemediationDismissalChecker,
  feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }

  let(:purl_type) { 'gem' }
  let(:vulnerability) do
    instance_double(Vulnerability, sbom_occurrences: [instance_double(Sbom::Occurrence, purl_type: purl_type)])
  end

  subject(:checker) { described_class.new(project: project, vulnerability: vulnerability, sbom_occurrence: nil) }

  def output_with(*name_version_pairs)
    dependencies = name_version_pairs.map do |name, version|
      DependencyManagement::SecurityUpdate::OutputParser::DependencyChange.new(
        name: name, previous_version: '0.0.0', version: version
      )
    end

    DependencyManagement::SecurityUpdate::OutputParser::Result.new(dependencies: dependencies, updated_files: [])
  end

  def dismissed_mr(title, remediation: true)
    prefix = DependencyManagement::SecurityUpdate::Request::BRANCH_PREFIX
    branch = remediation ? "#{prefix}/rails-6.x" : 'some-other-branch'

    instance_double(MergeRequest, title: title, source_branch: branch)
  end

  def stub_finder(merge_requests)
    finder = instance_double(DependencyManagement::SecurityUpdate::UserClosedRemediationsFinder)
    allow(DependencyManagement::SecurityUpdate::UserClosedRemediationsFinder)
      .to receive(:new).with(project: project).and_return(finder)
    allow(finder).to receive(:for_vulnerability).with(vulnerability).and_return(merge_requests)
  end

  describe '#dismissed?' do
    context 'when there are no user-closed remediation MRs' do
      before do
        stub_finder([])
      end

      it 'returns false' do
        expect(checker.dismissed?(output_with(['rails', '6.1.5']))).to be(false)
      end
    end

    context 'when the dismissed MR has a conventional title' do
      before do
        stub_finder([dismissed_mr('chore(deps): [security] update rails from 6.1.4 to 6.1.5')])
      end

      it 'is dismissed for the same version' do
        expect(checker.dismissed?(output_with(['rails', '6.1.5']))).to be(true)
      end

      it 'is not dismissed for a newer version' do
        expect(checker.dismissed?(output_with(['rails', '6.1.6']))).to be(false)
      end
    end

    context 'when a same-finding MR dismissed a version' do
      before do
        stub_finder([dismissed_mr('Security: Update rails from 6.1.4 to 6.1.5')])
      end

      it 'is dismissed for the same version' do
        expect(checker.dismissed?(output_with(['rails', '6.1.5']))).to be(true)
      end

      it 'is dismissed for a lower version' do
        expect(checker.dismissed?(output_with(['rails', '6.1.4']))).to be(true)
      end

      it 'is not dismissed for a newer version (resurface)' do
        expect(checker.dismissed?(output_with(['rails', '6.1.6']))).to be(false)
      end
    end

    context 'when the closed MR is not on a remediation branch' do
      before do
        stub_finder([dismissed_mr('Security: Update rails from 6.1.4 to 6.1.5', remediation: false)])
      end

      it 'ignores it' do
        expect(checker.dismissed?(output_with(['rails', '6.1.5']))).to be(false)
      end
    end

    context 'with several dismissals for the same dependency' do
      before do
        stub_finder([
          dismissed_mr('Security: Update rails from 6.1.4 to 6.1.5'),
          dismissed_mr('Security: Update rails from 6.1.5 to 6.1.7')
        ])
      end

      it 'uses the highest dismissed version' do
        expect(checker.dismissed?(output_with(['rails', '6.1.7']))).to be(true)
      end
    end

    context 'when a proposed dependency has no matching dismissal' do
      before do
        stub_finder([dismissed_mr('Security: Update rails from 6.1.4 to 6.1.5')])
      end

      it 'is not dismissed (something new to propose)' do
        expect(checker.dismissed?(output_with(['rails', '6.1.5'], ['nokogiri', '1.2.3']))).to be(false)
      end
    end

    context 'with a Maven ecosystem (non-semver ordering)' do
      let(:purl_type) { 'maven' }

      before do
        stub_finder([dismissed_mr('Security: Update foo from 1.0-alpha to 1.0')])
      end

      it 'treats a stable release as newer than its pre-release' do
        expect(checker.dismissed?(output_with(['foo', '1.0']))).to be(true)
      end
    end

    context 'when a version cannot be parsed' do
      before do
        stub_finder([dismissed_mr('Security: Update rails from 6.1.4 to 6.1.5')])
        allow(SemverDialects).to receive(:parse_version).and_raise(SemverDialects::Error.new('unparseable'))
      end

      it 'logs an error and does not suppress' do
        expect(Gitlab::AppLogger).to receive(:error).with(
          hash_including(
            message: 'DependencyManagement: failed to compare versions for remediation dismissal',
            package_type: 'gem'
          )
        )

        expect(checker.dismissed?(output_with(['rails', '6.1.5']))).to be(false)
      end
    end

    context 'when the versions are not comparable (<=> returns nil)' do
      before do
        stub_finder([dismissed_mr('Security: Update rails from 6.1.4 to 6.1.5')])
        allow_next_instances_of_semver_dialects_result_to_be_incomparable
      end

      def allow_next_instances_of_semver_dialects_result_to_be_incomparable
        incomparable = Class.new { def <=>(_other); end }.new

        allow(SemverDialects).to receive(:parse_version).and_return(incomparable)
      end

      it 'logs an error and does not suppress (does not raise NoMethodError)' do
        expect(Gitlab::AppLogger).to receive(:error).with(
          hash_including(
            message: 'DependencyManagement: failed to compare versions for remediation dismissal',
            package_type: 'gem'
          )
        )

        expect(checker.dismissed?(output_with(['rails', '6.1.5']))).to be(false)
      end
    end
  end

  describe '#dismissed? against the persisted record' do
    let_it_be(:component) { create(:sbom_component, :bundler, name: 'rails') }
    let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
    let_it_be(:sbom_occurrence) do
      create(:sbom_occurrence,
        project: project,
        component: component,
        package_manager: 'bundler',
        input_file_path: 'Gemfile.lock')
    end

    let(:state) { :dismissed }
    let(:target_version) { '6.1.5' }

    subject(:checker) do
      described_class.new(project: project, vulnerability: vulnerability, sbom_occurrence: sbom_occurrence)
    end

    before_all do
      create(:sbom_occurrences_vulnerability, occurrence: sbom_occurrence, vulnerability: vulnerability)
    end

    before do
      create(:dependency_management_remediation,
        project: project,
        purl_type: :gem,
        package_name: 'rails',
        input_file_path: 'Gemfile.lock',
        current_version: sbom_occurrence.version,
        target_version: target_version,
        state: state)
    end

    it 'is dismissed when proposing the version that was dismissed' do
      expect(checker.dismissed?(output_with(['rails', '6.1.5']))).to be(true)
    end

    it 'is dismissed when proposing an older version' do
      expect(checker.dismissed?(output_with(['rails', '6.1.4']))).to be(true)
    end

    it 'resurfaces for a newer version' do
      expect(checker.dismissed?(output_with(['rails', '6.1.6']))).to be(false)
    end

    it 'ignores dependencies the updater moved alongside the remediated one' do
      expect(checker.dismissed?(output_with(['rails', '6.1.5'], ['nokogiri', '1.2.3']))).to be(true)
    end

    %i[open merged].each do |other_state|
      context "when the record is #{other_state}" do
        let(:state) { other_state }

        it 'is not dismissed' do
          expect(checker.dismissed?(output_with(['rails', '6.1.5']))).to be(false)
        end
      end
    end

    context 'when the remediated component is absent from the output' do
      it 'is not dismissed' do
        expect(checker.dismissed?(output_with(['nokogiri', '1.2.3']))).to be(false)
      end
    end

    context 'when the dismissal was recorded against another installed version' do
      let_it_be(:other_version_occurrence) do
        create(:sbom_occurrence,
          project: project,
          component: component,
          component_version: create(:sbom_component_version, component: component, version: '5.0.0'),
          package_manager: 'bundler',
          input_file_path: 'Gemfile.lock')
      end

      subject(:checker) do
        described_class.new(project: project, vulnerability: vulnerability, sbom_occurrence: other_version_occurrence)
      end

      it 'is not dismissed' do
        expect(checker.dismissed?(output_with(['rails', '6.1.5']))).to be(false)
      end
    end

    context 'when the occurrence is another manifest' do
      let_it_be(:other_occurrence) do
        create(:sbom_occurrence,
          project: project,
          component: component,
          package_manager: 'bundler',
          input_file_path: 'other/Gemfile.lock')
      end

      subject(:checker) do
        described_class.new(project: project, vulnerability: vulnerability, sbom_occurrence: other_occurrence)
      end

      before_all do
        create(:sbom_occurrences_vulnerability, occurrence: other_occurrence, vulnerability: vulnerability)
      end

      it 'is not dismissed' do
        expect(checker.dismissed?(output_with(['rails', '6.1.5']))).to be(false)
      end
    end

    context 'when the occurrence could not be resolved' do
      subject(:checker) { described_class.new(project: project, vulnerability: vulnerability, sbom_occurrence: nil) }

      it 'does not read another manifest\'s row' do
        expect(checker.dismissed?(output_with(['rails', '6.1.5']))).to be(false)
      end
    end

    context 'with a Maven dependency' do
      let_it_be(:maven_component) { create(:sbom_component, name: 'org.apache/commons-text', purl_type: :maven) }
      let_it_be(:maven_occurrence) do
        create(:sbom_occurrence,
          project: project,
          component: maven_component,
          package_manager: 'maven',
          input_file_path: 'pom.xml')
      end

      let_it_be(:maven_vulnerability) { create(:vulnerability, :with_finding, project: project) }

      subject(:checker) do
        described_class.new(project: project, vulnerability: maven_vulnerability, sbom_occurrence: maven_occurrence)
      end

      before_all do
        create(:sbom_occurrences_vulnerability, occurrence: maven_occurrence, vulnerability: maven_vulnerability)
      end

      before do
        create(:dependency_management_remediation,
          project: project,
          purl_type: :maven,
          package_name: 'org.apache/commons-text',
          input_file_path: 'pom.xml',
          current_version: maven_occurrence.version,
          target_version: '1.10.0',
          state: :dismissed)
      end

      it 'finds the proposal under the updater spelling' do
        expect(checker.dismissed?(output_with(['org.apache:commons-text', '1.10.0']))).to be(true)
      end
    end
  end
end
