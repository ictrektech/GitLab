# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfileProject, feature_category: :security_testing_configuration do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, namespace: group) }
  let_it_be(:scan_profile) { create(:security_scan_profile, namespace: group) }

  describe 'associations' do
    it { is_expected.to belong_to(:scan_profile).class_name('Security::ScanProfile').required }
    it { is_expected.to belong_to(:project).required }
  end

  describe 'validations' do
    subject { create(:security_scan_profile_project, scan_profile: scan_profile, project: project) }

    it { is_expected.to validate_uniqueness_of(:project_id).scoped_to(:security_scan_profile_id) }
  end

  describe 'scopes' do
    let_it_be(:root_namespace) { create(:group) }
    let_it_be(:other_namespace) { create(:group) }

    let_it_be(:project_in_root) { create(:project, namespace: root_namespace) }
    let_it_be(:project_in_other) { create(:project, namespace: other_namespace) }
    let_it_be(:project_1) { create(:project, namespace: group) }
    let_it_be(:project_2) { create(:project, namespace: group) }
    let_it_be(:project_3) { create(:project, namespace: group) }

    let_it_be(:scan_profile_in_root) { create(:security_scan_profile, namespace: root_namespace) }
    let_it_be(:scan_profile_in_other) { create(:security_scan_profile, namespace: other_namespace) }
    let_it_be(:scan_profile_1) { create(:security_scan_profile, namespace: group, name: "profile 1") }
    let_it_be(:scan_profile_2) { create(:security_scan_profile, namespace: group, name: "profile 2") }

    let_it_be(:association_in_root) do
      create(:security_scan_profile_project, scan_profile: scan_profile_in_root, project: project_in_root)
    end

    let_it_be(:association_in_other) do
      create(:security_scan_profile_project, scan_profile: scan_profile_in_other, project: project_in_other)
    end

    let_it_be(:association_1) do
      create(:security_scan_profile_project, scan_profile: scan_profile_1, project: project_1)
    end

    let_it_be(:association_2) do
      create(:security_scan_profile_project, scan_profile: scan_profile_1, project: project_2)
    end

    let_it_be(:association_3) do
      create(:security_scan_profile_project, scan_profile: scan_profile_1, project: project_3)
    end

    let_it_be(:association_other_profile) do
      create(:security_scan_profile_project, scan_profile: scan_profile_2, project: project_1)
    end

    let_it_be(:all_associations) do
      [
        association_in_root,
        association_in_other,
        association_1,
        association_2,
        association_3,
        association_other_profile
      ]
    end

    describe '.for_projects_and_profile' do
      let_it_be(:association1) do
        create(:security_scan_profile_project, scan_profile: scan_profile, project: project)
      end

      let_it_be(:association2) do
        create(:security_scan_profile_project, scan_profile: scan_profile, project: project_1)
      end

      let_it_be(:association_different_profile) do
        create(:security_scan_profile_project, scan_profile: scan_profile_in_other, project: project)
      end

      let_it_be(:association_unrelated) do
        create(:security_scan_profile_project, scan_profile: scan_profile_in_other, project: project_2)
      end

      it 'returns associations for the given projects and scan profile' do
        result = described_class.for_projects_and_profile([project.id, project_1.id], scan_profile)

        expect(result).to contain_exactly(association1, association2)
      end

      it 'returns empty when no projects match' do
        result = described_class.for_projects_and_profile([non_existing_record_id], scan_profile)

        expect(result).to be_empty
      end

      it 'returns empty when projects exist but not for the given profile' do
        result = described_class.for_projects_and_profile([project_2.id], scan_profile)

        expect(result).to be_empty
      end
    end

    describe '.not_in_root_namespace' do
      it 'returns associations where scan profile is not in the given root namespace' do
        result = described_class.not_in_root_namespace(root_namespace)

        expect(result).to match_array(all_associations - [association_in_root])
      end

      it 'returns associations in root namespace when querying for other namespace' do
        result = described_class.not_in_root_namespace(other_namespace)

        expect(result).to match_array(all_associations - [association_in_other])
      end
    end

    describe '.by_project_id' do
      it 'returns associations for the given project' do
        result = described_class.by_project_id(project_1.id)

        expect(result).to contain_exactly(association_1, association_other_profile)
      end
    end

    describe '.unarchived' do
      let_it_be(:archived_association) do
        create(:security_scan_profile_project, scan_profile: scan_profile_2, project: project_2, archived: true)
      end

      it 'excludes associations flagged as archived' do
        result = described_class.for_scan_profiles(scan_profile_2.id).unarchived

        expect(result).to contain_exactly(association_other_profile)
      end
    end

    describe '.for_scan_profiles' do
      it 'returns associations for the given scan profile' do
        result = described_class.for_scan_profiles(scan_profile_1.id)

        expect(result).to contain_exactly(association_1, association_2, association_3)
      end
    end

    describe '.project_ids_with_profile_type' do
      let_it_be(:scan_type) { scan_profile_1.scan_type }

      it 'returns projects with a non-deleted profile of the type in the namespace' do
        result = described_class.project_ids_with_profile_type([project_1.id, project_in_root.id], group.id, scan_type)

        expect(result).to contain_exactly(project_1.id)
      end

      it 'excludes projects whose profile has a different scan type' do
        result = described_class.project_ids_with_profile_type([project_1.id], group.id, :secret_detection)

        expect(result).to be_empty
      end

      it 'returns each project once so the limit does not drop projects with several matching profiles' do
        # Fails without `.distinct`: the multi-link project's duplicate rows come first (insertion order matters).
        namespace = create(:group)
        multi_link_project = create(:project, namespace: namespace)
        single_link_project = create(:project, namespace: namespace)
        profile_a = create(:security_scan_profile, namespace: namespace, name: 'A', scan_type: scan_type)
        profile_b = create(:security_scan_profile, namespace: namespace, name: 'B', scan_type: scan_type)
        profile_c = create(:security_scan_profile, namespace: namespace, name: 'C', scan_type: scan_type)
        create(:security_scan_profile_project, scan_profile: profile_a, project: multi_link_project)
        create(:security_scan_profile_project, scan_profile: profile_b, project: multi_link_project)
        create(:security_scan_profile_project, scan_profile: profile_c, project: single_link_project)

        result = described_class.project_ids_with_profile_type(
          [multi_link_project.id, single_link_project.id], namespace.id, scan_type)

        expect(result).to contain_exactly(multi_link_project.id, single_link_project.id)
      end

      it 'ignores soft-deleted profiles' do
        deleted = create(:security_scan_profile, namespace: other_namespace, name: 'Deleted',
          scan_type: :dependency_scanning, deleted_at: Time.current)
        deleted_project = create(:project, namespace: other_namespace)
        create(:security_scan_profile_project, scan_profile: deleted, project: deleted_project)

        result = described_class.project_ids_with_profile_type(
          [deleted_project.id], other_namespace.id, deleted.scan_type)

        expect(result).to be_empty
      end
    end

    describe '.project_ids' do
      it 'plucks project ids from the current relation' do
        result = described_class.for_scan_profiles(scan_profile_1.id).project_ids

        expect(result).to contain_exactly(project_1.id, project_2.id, project_3.id)
      end
    end
  end

  describe 'archived denormalization' do
    let_it_be(:other_scan_profile) { create(:security_scan_profile, namespace: group, name: 'other profile') }

    let_it_be_with_reload(:association) do
      create(:security_scan_profile_project, scan_profile: scan_profile, project: project)
    end

    describe '.attached_project_ids' do
      let_it_be(:unattached_project) { create(:project, namespace: group) }

      let_it_be(:second_association) do
        create(:security_scan_profile_project, scan_profile: other_scan_profile, project: project)
      end

      it 'returns each attached project once, however many profiles it has' do
        result = described_class.attached_project_ids([project.id, unattached_project.id])

        expect(result).to contain_exactly(project.id)
      end

      it 'returns an empty array for blank input without querying' do
        expect(described_class).not_to receive(:by_project_id)

        expect(described_class.attached_project_ids([])).to eq([])
        expect(described_class.attached_project_ids(nil)).to eq([])
      end
    end

    describe '.update_archived_for' do
      it 'flags the rows as archived' do
        expect { described_class.update_archived_for([project.id], archived: true) }
          .to change { association.reload.archived }.from(false).to(true)
      end

      it 'clears the flag' do
        association.update!(archived: true)

        expect { described_class.update_archived_for([project.id], archived: false) }
          .to change { association.reload.archived }.from(true).to(false)
      end

      it 'writes no rows when the value already matches' do
        expect(described_class.update_archived_for([project.id], archived: false)).to eq(0)
      end

      it 'returns zero for blank input' do
        expect(described_class.update_archived_for([], archived: true)).to eq(0)
        expect(described_class.update_archived_for(nil, archived: true)).to eq(0)
      end
    end

    describe '.sync_archived_for' do
      let_it_be_with_reload(:archived_subgroup) { create(:group, parent: group) }
      let_it_be(:project_in_archived_subgroup) { create(:project, namespace: archived_subgroup) }

      let_it_be_with_reload(:subgroup_association) do
        create(:security_scan_profile_project,
          scan_profile: scan_profile, project: project_in_archived_subgroup)
      end

      before do
        archived_subgroup.namespace_settings.update!(archived: true)
      end

      # The group archive services flatten descendant state today, so a mixed batch
      # cannot be produced by driving them -- it has to be built directly.
      it 'computes each project archived state independently' do
        described_class.sync_archived_for([project.id, project_in_archived_subgroup.id])

        expect(subgroup_association.reload.archived).to be(true)
        expect(association.reload.archived).to be(false)
      end

      it 'returns the number of rows written' do
        expect(described_class.sync_archived_for([project.id, project_in_archived_subgroup.id])).to eq(1)
      end

      context 'with self-archived projects' do
        let_it_be(:self_archived_project) { create(:project, :archived, namespace: group) }
        let_it_be(:more_self_archived_projects) { create_list(:project, 2, :archived, namespace: group) }

        before_all do
          [self_archived_project, *more_self_archived_projects].each do |archived_project|
            create(:security_scan_profile_project, scan_profile: scan_profile, project: archived_project)
          end
        end

        # `self_or_ancestors_archived?` reaches `project_namespace` for a self-archived
        # project, so without that preload each one costs an extra query.
        it 'does not issue a query per archived project' do
          control = ActiveRecord::QueryRecorder.new do
            described_class.sync_archived_for([self_archived_project.id])
          end

          expect { described_class.sync_archived_for(more_self_archived_projects.map(&:id)) }
            .not_to exceed_query_limit(control)
        end
      end
    end
  end

  context 'with loose foreign key on security_scan_profiles_projects.project_id' do
    it_behaves_like 'cleanup by a loose foreign key' do
      let_it_be(:parent) { project }
      let_it_be(:model) { create(:security_scan_profile_project, scan_profile: scan_profile, project: parent) }
    end
  end
end
