# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::Remediation, feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }

  subject(:remediation) { build(:dependency_management_remediation, project: project) }

  it { is_expected.to be_valid }

  describe 'associations' do
    it { is_expected.to belong_to(:project).required }
    it { is_expected.to belong_to(:merge_request).optional }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:purl_type).with_values(::Enums::Sbom.purl_types) }
    it { is_expected.to define_enum_for(:state).with_values(described_class::STATES) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:purl_type) }
    it { is_expected.to validate_presence_of(:state) }
    it { is_expected.to validate_presence_of(:package_name) }
    it { is_expected.to validate_length_of(:package_name).is_at_most(255) }
    it { is_expected.to validate_presence_of(:current_version) }
    it { is_expected.to validate_length_of(:current_version).is_at_most(255) }
    it { is_expected.to validate_presence_of(:target_version) }
    it { is_expected.to validate_length_of(:target_version).is_at_most(255) }
    it { is_expected.to validate_length_of(:input_file_path).is_at_most(1024) }

    it 'accepts a blank input_file_path for a root manifest' do
      remediation.input_file_path = ''

      expect(remediation).to be_valid
    end

    it 'rejects a nil input_file_path' do
      remediation.input_file_path = nil

      expect(remediation).not_to be_valid
    end
  end

  describe 'uniqueness of the dependency location' do
    let(:attributes) do
      { project: project, purl_type: :npm, package_name: 'lodash', input_file_path: 'package.json' }
    end

    before do
      create(:dependency_management_remediation, **attributes)
    end

    it 'rejects a second row for the same location' do
      expect { create(:dependency_management_remediation, **attributes) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    # The validation races, so the index is what actually enforces this.
    it 'rejects a second row even when validations are skipped' do
      duplicate = build(:dependency_management_remediation, **attributes)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same dependency in another manifest' do
      expect { create(:dependency_management_remediation, **attributes, input_file_path: 'ui/package.json') }
        .to change { described_class.count }.by(1)
    end

    it 'allows the same package name under another ecosystem' do
      expect { create(:dependency_management_remediation, **attributes, purl_type: :pypi) }
        .to change { described_class.count }.by(1)
    end

    # npm allows the same package installed at several versions in one
    # manifest, each remediated on its own.
    it 'allows the same dependency at another installed version' do
      expect { create(:dependency_management_remediation, **attributes, current_version: '1.2.0') }
        .to change { described_class.count }.by(1)
    end
  end

  describe '.record_proposal' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    def record(target_version:, merge_request: nil, current_version: '4.17.11')
      described_class.record_proposal(
        project: project,
        merge_request: merge_request || self.merge_request,
        purl_type: 'npm',
        package_name: 'lodash',
        input_file_path: 'package.json',
        current_version: current_version,
        target_version: target_version
      )
    end

    it 'inserts a row in the open state' do
      expect { record(target_version: '4.17.21') }.to change { described_class.count }.by(1)

      expect(described_class.last).to have_attributes(
        project_id: project.id,
        merge_request_id: merge_request.id,
        purl_type: 'npm',
        package_name: 'lodash',
        input_file_path: 'package.json',
        current_version: '4.17.11',
        target_version: '4.17.21',
        state: 'open'
      )
    end

    it 'stores a nil input_file_path as an empty string' do
      described_class.record_proposal(
        project: project, merge_request: merge_request, purl_type: 'npm',
        package_name: 'lodash', input_file_path: nil, current_version: '4.17.11', target_version: '4.17.21'
      )

      expect(described_class.last.input_file_path).to eq('')
    end

    # A different installed version is a different remediation, not a resurface.
    it 'keeps rows for each installed version of the dependency' do
      record(target_version: '4.17.21')

      expect { record(target_version: '4.17.21', current_version: '1.2.0') }
        .to change { described_class.count }.by(1)
    end

    context 'when the location already has a row' do
      let_it_be(:newer_merge_request) do
        create(:merge_request, source_project: project, source_branch: 'dependency-management/lodash-5.x')
      end

      before do
        record(target_version: '4.17.21')
        described_class.last.update!(state: :dismissed)
      end

      # Safe because we only propose again above what was dismissed.
      it 'overwrites it rather than adding a second row' do
        expect { record(target_version: '4.17.22', merge_request: newer_merge_request) }
          .not_to change { described_class.count }

        expect(described_class.last).to have_attributes(
          target_version: '4.17.22',
          state: 'open',
          merge_request_id: newer_merge_request.id
        )
      end

      # The row is open again, so a leftover date would read as a live dismissal.
      it 'clears the dismissal date when it resurfaces' do
        described_class.last.update!(dismissed_at: 1.day.ago)

        record(target_version: '4.17.22', merge_request: newer_merge_request)

        expect(described_class.last.dismissed_at).to be_nil
      end

      it 'keeps the original created_at' do
        original = described_class.last.created_at

        travel_to(1.hour.from_now) do
          record(target_version: '4.17.22')
        end

        expect(described_class.last.created_at).to be_within(1.second).of(original)
        expect(described_class.last.updated_at).to be > original
      end

      # The title-based check misses unparseable titles, so without this the row
      # loses both the decision and the merge request that carried it.
      it 'keeps the dismissal when the target has not moved' do
        record(target_version: '4.17.21', merge_request: newer_merge_request)

        expect(described_class.last).to have_attributes(
          target_version: '4.17.21',
          state: 'dismissed',
          merge_request_id: merge_request.id
        )
      end

      # updated_at moves with every attempt, which is why the date has a column.
      it 'holds the dismissal date still across re-proposals' do
        dismissed_at = 1.day.ago
        described_class.last.update!(dismissed_at: dismissed_at)

        record(target_version: '4.17.21', merge_request: newer_merge_request)

        expect(described_class.last.dismissed_at).to be_within(1.second).of(dismissed_at)
      end

      it 'keeps the dismissal and its ceiling for a lower target' do
        record(target_version: '4.17.15', merge_request: newer_merge_request)

        expect(described_class.last).to have_attributes(
          target_version: '4.17.21',
          state: 'dismissed',
          merge_request_id: merge_request.id
        )
      end

      # Repointing would make reopening the merge request that was actually
      # closed a silent no-op, which is the recovery path for a close nobody meant.
      it 'leaves the dismissal answerable to the merge request that was closed' do
        record(target_version: '4.17.21', merge_request: newer_merge_request)

        expect { described_class.withdraw_dismissal_for_merge_request(newer_merge_request) }
          .not_to change { described_class.last.state }.from('dismissed')

        expect { described_class.withdraw_dismissal_for_merge_request(merge_request) }
          .to change { described_class.last.state }.from('dismissed').to('open')
      end

      # Going quiet is the worse failure, so an unparseable pair resurfaces.
      it 'resurfaces when the versions cannot be compared' do
        record(target_version: 'not-a-version', merge_request: newer_merge_request)

        expect(described_class.last).to have_attributes(
          target_version: 'not-a-version',
          state: 'open'
        )
      end

      # An ecosystem with no semver dialect cannot be compared, so it resurfaces
      # for the same reason an unparseable version does.
      it 'resurfaces when the ecosystem has no dialect' do
        expect(described_class.send(:higher_version?, '4.17.22', '4.17.21', nil)).to be(true)
      end

      it 'resurfaces when the version parser raises' do
        allow(SemverDialects).to receive(:parse_version).and_raise(SemverDialects::Error.new('boom'))

        record(target_version: '4.17.22', merge_request: newer_merge_request)

        expect(described_class.last.state).to eq('open')
      end
    end
  end

  describe '.for_occurrence' do
    let_it_be(:component) { create(:sbom_component, :bundler, name: 'rails') }
    let_it_be(:occurrence) do
      create(:sbom_occurrence, project: project, component: component).tap do |occurrence|
        occurrence.update_column(:input_file_path, nil)
      end
    end

    let_it_be(:remediation) do
      create(:dependency_management_remediation,
        project: project,
        purl_type: :gem,
        package_name: 'rails',
        input_file_path: '',
        current_version: occurrence.version)
    end

    it 'matches an occurrence without a path to the row stored with an empty one' do
      expect(described_class.for_occurrence(project, occurrence)).to eq(remediation)
    end

    it 'returns nil without an occurrence' do
      expect(described_class.for_occurrence(project, nil)).to be_nil
    end
  end

  describe '.transition_for_merge_request' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }
    let_it_be_with_reload(:remediation) do
      create(:dependency_management_remediation, project: project, merge_request: merge_request)
    end

    # A second real merge request, so a scope widened to every non-null row
    # cannot stay green. The nil row keeps the loose foreign key arm pinned.
    let_it_be_with_reload(:unrelated) do
      create(:dependency_management_remediation,
        project: project,
        package_name: 'axios',
        merge_request: create(:merge_request, source_project: project, source_branch: 'other-branch'))
    end

    let_it_be_with_reload(:orphaned) do
      create(:dependency_management_remediation, project: project, package_name: 'faraday', merge_request: nil)
    end

    it 'moves every row for that merge request' do
      expect { described_class.transition_for_merge_request(merge_request, :dismissed) }
        .to change { remediation.reload.state }.from('open').to('dismissed')
    end

    it 'accepts a string state' do
      expect { described_class.transition_for_merge_request(merge_request, 'merged') }
        .to change { remediation.reload.state }.to('merged')
    end

    it 'dates the dismissal from the close rather than from this call' do
      closed_at = 2.hours.ago
      merge_request.metrics.update!(latest_closed_at: closed_at)

      described_class.transition_for_merge_request(merge_request, :dismissed)

      expect(remediation.reload.dismissed_at).to be_within(1.second).of(closed_at)
    end

    # A merge request closed before metrics existed has no close time to read.
    it 'falls back to now when the close was not recorded' do
      merge_request.metrics.update!(latest_closed_at: nil)

      freeze_time do
        described_class.transition_for_merge_request(merge_request, :dismissed)

        expect(remediation.reload.dismissed_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'clears the dismissal date for any other state' do
      remediation.update!(state: :dismissed, dismissed_at: 1.day.ago)

      expect { described_class.transition_for_merge_request(merge_request, :merged) }
        .to change { remediation.reload.dismissed_at }.to(nil)
    end

    # A nil id would otherwise match every orphaned row, in every project.
    it 'touches nothing for a merge request without an id' do
      expect { described_class.transition_for_merge_request(MergeRequest.new, :dismissed) }
        .to not_change { remediation.reload.state }
        .and not_change { unrelated.reload.state }
        .and not_change { orphaned.reload.state }
    end

    it 'leaves rows for other merge requests alone' do
      expect { described_class.transition_for_merge_request(merge_request, :dismissed) }
        .not_to change { unrelated.reload.state }
    end

    it 'raises on an unknown state rather than writing a meaningless value' do
      expect { described_class.transition_for_merge_request(merge_request, :nonsense) }
        .to raise_error(KeyError)
    end
  end

  describe '.withdraw_dismissal_for_merge_request' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    let_it_be_with_reload(:dismissed) do
      create(:dependency_management_remediation,
        project: project, merge_request: merge_request, state: :dismissed)
    end

    let_it_be_with_reload(:elsewhere) do
      create(:dependency_management_remediation,
        project: project, package_name: 'elsewhere', merge_request: nil, state: :dismissed)
    end

    it 'returns a dismissed row to open' do
      expect { described_class.withdraw_dismissal_for_merge_request(merge_request) }
        .to change { dismissed.reload.state }.from('dismissed').to('open')
    end

    it 'clears the dismissal date' do
      dismissed.update!(dismissed_at: 1.day.ago)

      expect { described_class.withdraw_dismissal_for_merge_request(merge_request) }
        .to change { dismissed.reload.dismissed_at }.to(nil)
    end

    context 'with rows in other states' do
      let_it_be_with_reload(:merged) do
        create(:dependency_management_remediation,
          project: project, package_name: 'merged-one', merge_request: merge_request, state: :merged)
      end

      # A merged bump has already landed, so reopening must not resurrect it.
      it 'leaves a merged row alone' do
        expect { described_class.withdraw_dismissal_for_merge_request(merge_request) }
          .not_to change { merged.reload.state }.from('merged')
      end
    end

    it 'leaves rows for other merge requests alone' do
      expect { described_class.withdraw_dismissal_for_merge_request(merge_request) }
        .not_to change { elsewhere.reload.state }.from('dismissed')
    end
  end

  context 'with loose foreign key on dependency_management_remediations.project_id' do
    it_behaves_like 'cleanup by a loose foreign key', on_delete: :async_delete do
      let_it_be(:parent) { create(:project) }
      let_it_be(:model) { create(:dependency_management_remediation, project: parent) }
    end
  end

  context 'with loose foreign key on dependency_management_remediations.merge_request_id' do
    # Nullify, not delete: a dismissal must survive its merge request.
    it_behaves_like 'cleanup by a loose foreign key', on_delete: :async_nullify do
      let_it_be(:parent) { create(:merge_request) }
      let_it_be(:model) do
        create(:dependency_management_remediation, project: parent.source_project, merge_request: parent)
      end
    end
  end
end
