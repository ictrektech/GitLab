# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::ScopedProjectsResolver, feature_category: :security_policy_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:other_group) { create(:group, organization: organization) }

  let_it_be(:group_project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }
  let_it_be(:other_group_project) { create(:project, group: other_group) }
  let_it_be(:foreign_project) { create(:project) }

  # The resolver reads the policy_scope document only, so these policies keep a
  # deployment trigger and have no tie to the settings trigger vocabulary.
  def organization_policy(policy_scope = nil)
    create(:govern_policy, :without_namespace, organization: organization, policy_scope: policy_scope)
  end

  def group_policy(namespace, policy_scope = nil)
    create(:govern_policy, namespace: namespace, organization: organization, policy_scope: policy_scope)
  end

  def resolve(policy)
    [].tap do |projects|
      described_class.new(policy).each_candidate_batch { |batch| projects.concat(batch) }
    end
  end

  describe '#each_candidate_batch' do
    it 'covers the whole organization when the policy names no scope' do
      expect(resolve(organization_policy)).to contain_exactly(group_project, subgroup_project, other_group_project)
    end

    it 'treats an empty scope document like no scope at all' do
      expect(resolve(organization_policy({}))).to contain_exactly(group_project, subgroup_project,
        other_group_project)
    end

    it 'treats a malformed dimension as naming no records' do
      scope = { 'projects' => 'all', 'groups' => [{ 'id' => group.id }] }

      expect(resolve(organization_policy(scope))).to contain_exactly(group_project, subgroup_project,
        other_group_project)
    end

    it 'keeps a group-authored policy inside its own subtree' do
      expect(resolve(group_policy(group))).to contain_exactly(group_project, subgroup_project)
    end

    it 'covers nothing when the authoring namespace no longer exists' do
      policy = group_policy(group)
      policy.update_column(:namespace_id, non_existing_record_id)

      expect(resolve(policy.reload)).to be_empty
    end

    describe 'subtree containment' do
      it 'ignores a document that includes a project outside the subtree' do
        scope = { 'projects' => { 'including' => [{ 'id' => other_group_project.id }] } }

        expect(resolve(group_policy(group, scope))).to be_empty
      end

      it 'ignores a document that includes a group outside the subtree' do
        scope = { 'groups' => { 'including' => [{ 'id' => other_group.id }] } }

        expect(resolve(group_policy(group, scope))).to be_empty
      end

      it 'cuts a compliance framework inclusion down to the subtree' do
        framework = create(:compliance_framework, namespace: group)
        create(:compliance_framework_project_setting,
          project: subgroup_project, compliance_management_framework: framework)
        create(:compliance_framework_project_setting,
          project: other_group_project, compliance_management_framework: framework)

        scope = { 'compliance_frameworks' => [{ 'id' => framework.id }] }

        expect(resolve(group_policy(group, scope))).to contain_exactly(subgroup_project)
      end
    end

    describe 'inclusions' do
      it 'takes the projects the document names' do
        scope = { 'projects' => { 'including' => [{ 'id' => group_project.id }] } }

        expect(resolve(organization_policy(scope))).to contain_exactly(group_project)
      end

      it 'takes a named group with its descendants' do
        scope = { 'groups' => { 'including' => [{ 'id' => group.id }] } }

        expect(resolve(organization_policy(scope))).to contain_exactly(group_project, subgroup_project)
      end

      it 'reads a bare id as well as an { id } entry' do
        scope = { 'projects' => { 'including' => [group_project.id] } }

        expect(resolve(organization_policy(scope))).to contain_exactly(group_project)
      end

      it 'reads a string id, which the store coerces when compiling the scope' do
        scope = { 'projects' => { 'including' => [{ 'id' => group_project.id.to_s }] } }

        expect(resolve(organization_policy(scope))).to contain_exactly(group_project)
      end

      it 'unions the dimensions instead of intersecting them' do
        scope = {
          'projects' => { 'including' => [{ 'id' => other_group_project.id }] },
          'groups' => { 'including' => [{ 'id' => subgroup.id }] }
        }

        expect(resolve(organization_policy(scope))).to contain_exactly(other_group_project, subgroup_project)
      end

      it 'yields a project two dimensions both name only once' do
        scope = {
          'projects' => { 'including' => [{ 'id' => subgroup_project.id }] },
          'groups' => { 'including' => [{ 'id' => group.id }] }
        }

        expect(resolve(organization_policy(scope))).to contain_exactly(group_project, subgroup_project)
      end

      it 'never reaches outside the organization' do
        scope = { 'projects' => { 'including' => [{ 'id' => foreign_project.id }] } }

        expect(resolve(organization_policy(scope))).to be_empty
      end

      it 'covers nothing when every named group has vanished' do
        scope = { 'groups' => { 'including' => [{ 'id' => non_existing_record_id }] } }

        expect(resolve(organization_policy(scope))).to be_empty
      end

      context 'with a compliance framework' do
        let_it_be(:framework) { create(:compliance_framework, namespace: group) }

        before_all do
          create(:compliance_framework_project_setting,
            project: subgroup_project, compliance_management_framework: framework)
        end

        it 'takes the projects the framework covers' do
          scope = { 'compliance_frameworks' => [{ 'id' => framework.id }] }

          expect(resolve(organization_policy(scope))).to contain_exactly(subgroup_project)
        end

        it 'yields a project a group and the framework both name only once' do
          scope = {
            'groups' => { 'including' => [{ 'id' => subgroup.id }] },
            'compliance_frameworks' => [{ 'id' => framework.id }]
          }

          expect(resolve(organization_policy(scope))).to contain_exactly(subgroup_project)
        end

        it 'yields a project the projects dimension and the framework both name only once' do
          scope = {
            'projects' => { 'including' => [{ 'id' => subgroup_project.id }] },
            'compliance_frameworks' => [{ 'id' => framework.id }]
          }

          expect(resolve(organization_policy(scope))).to contain_exactly(subgroup_project)
        end
      end
    end

    describe 'exclusions' do
      it 'drops the projects the document names' do
        scope = { 'projects' => { 'excluding' => [{ 'id' => group_project.id }] } }

        expect(resolve(organization_policy(scope))).to contain_exactly(subgroup_project, other_group_project)
      end

      it 'drops a named group with its descendants' do
        scope = { 'groups' => { 'excluding' => [{ 'id' => group.id }] } }

        expect(resolve(organization_policy(scope))).to contain_exactly(other_group_project)
      end

      it 'applies an exclusion to an inclusion of the same dimension' do
        scope = {
          'groups' => { 'including' => [{ 'id' => group.id }] },
          'projects' => { 'excluding' => [{ 'id' => subgroup_project.id }] }
        }

        expect(resolve(organization_policy(scope))).to contain_exactly(group_project)
      end

      context 'with an archived project' do
        let_it_be(:archived_project) { create(:project, :archived, group: other_group) }

        it 'drops it when the document excludes the archived type' do
          scope = { 'projects' => { 'excluding' => [{ 'type' => 'archived' }] } }

          expect(resolve(organization_policy(scope))).to contain_exactly(group_project, subgroup_project,
            other_group_project)
        end

        it 'keeps it otherwise' do
          expect(resolve(organization_policy)).to include(archived_project)
        end
      end

      context 'with a personal project' do
        let_it_be(:personal_project) do
          create(:project, namespace: create(:namespace, organization: organization))
        end

        it 'drops it when the document excludes the personal type' do
          scope = { 'projects' => { 'excluding' => [{ 'type' => 'personal' }] } }

          expect(resolve(organization_policy(scope))).to contain_exactly(group_project, subgroup_project,
            other_group_project)
        end

        it 'keeps it otherwise' do
          expect(resolve(organization_policy)).to include(personal_project)
        end
      end
    end

    describe 'batching' do
      it 'yields every candidate, and in batches' do
        batches = []
        described_class.new(organization_policy).each_candidate_batch(of: 1) { |batch| batches << batch.to_a }

        expect(batches.size).to eq(3)
        expect(batches.flatten).to contain_exactly(group_project, subgroup_project, other_group_project)
      end

      it 'batches each inclusion arm on its own' do
        scope = {
          'projects' => { 'including' => [{ 'id' => other_group_project.id }] },
          'groups' => { 'including' => [{ 'id' => subgroup.id }] }
        }

        batches = []
        described_class.new(organization_policy(scope)).each_candidate_batch(of: 1) { |batch| batches << batch.to_a }

        expect(batches.flatten).to contain_exactly(other_group_project, subgroup_project)
      end

      it 'filters the exclusions inside each batch, leaving some batches empty' do
        scope = { 'projects' => { 'excluding' => [{ 'id' => subgroup_project.id }] } }

        batches = []
        described_class.new(organization_policy(scope)).each_candidate_batch(of: 1) { |batch| batches << batch.to_a }

        expect(batches.size).to eq(3)
        expect(batches.flatten).to contain_exactly(group_project, other_group_project)
      end

      it 'loads the excluded groups once for all batches, and still drops them' do
        scope = { 'groups' => { 'excluding' => [{ 'id' => other_group.id }] } }

        expect(Group).to receive(:id_in).once.and_call_original

        batches = []
        described_class.new(organization_policy(scope)).each_candidate_batch(of: 1) { |batch| batches << batch.to_a }

        expect(batches.flatten).to contain_exactly(group_project, subgroup_project)
      end
    end
  end
end
