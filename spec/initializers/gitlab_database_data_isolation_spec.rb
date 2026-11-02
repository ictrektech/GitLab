# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Gitlab Organization Data Isolation', feature_category: :organization do
  let_it_be(:isolated_organization) { create(:organization, :isolated) }
  let_it_be(:other_organization) { create(:organization) }

  before do
    stub_current_organization(isolated_organization)
  end

  context 'when sharded by organization_id' do
    let_it_be(:group_isolated) { create(:group, organization: isolated_organization) }
    let_it_be(:group_other) { create(:group, organization: other_organization) }

    it 'returns only the current organization' do
      expect(Group.all.map(&:organization)).to contain_exactly(isolated_organization)
    end
  end

  context 'when sharded by user_id' do
    # This implicitly creates UserDetail records
    let_it_be(:user_isolated) { create(:user, organization: isolated_organization) }
    let_it_be(:user_other) { create(:user, organization: other_organization) }

    it 'returns only data from the isolated organization' do
      expect(UserDetail.all.map(&:user_id)).to contain_exactly(user_isolated.id)
    end
  end

  context 'when sharded by project_id' do
    # This implicitly creates ProjectPagesMetadatum records
    let_it_be(:project_isolated) { create(:project, organization: isolated_organization) }
    let_it_be(:project_other) { create(:project, organization: other_organization) }

    it 'returns only data from the isolated organization' do
      expect(ProjectPagesMetadatum.all.map(&:project_id)).to contain_exactly(project_isolated.id)
    end
  end

  context 'when the table has multiple sharding keys' do
    # Snippets are sharded by both project_id and organization_id. Tables with
    # multiple sharding keys are not isolated yet, because scoping them requires
    # a poorly performing OR condition.
    # See https://gitlab.com/gitlab-org/gitlab/-/issues/594726
    let_it_be(:snippet_isolated) { create(:personal_snippet, organization: isolated_organization) }
    let_it_be(:snippet_other) { create(:personal_snippet, organization: other_organization) }

    it 'does not apply the isolation scope' do
      expect(Snippet.all).to contain_exactly(snippet_isolated, snippet_other)
    end
  end

  context 'when sharded by namespace_id' do
    # This implicitly creates Namespace::Detail records
    let_it_be(:namespace_isolated) { create(:namespace, organization: isolated_organization) }
    let_it_be(:namespace_other) { create(:namespace, organization: other_organization) }

    it 'returns only data from the isolated organization' do
      expect(Namespace::Detail.all.map(&:namespace_id)).to contain_exactly(namespace_isolated.id)
    end
  end

  context 'when the table is on the CI database' do
    # The CI database has no projects or namespaces tables, so tables sharded
    # by project_id or namespace_id are scoped through the CI mirror tables.
    # In the test environment all tables share one database, so scoping through
    # projects would return the same rows: the SQL assertions prove the subquery
    # uses the mirror tables.
    context 'when sharded by project_id' do
      # The factories simulate the mirror sync, see spec/factories/projects.rb
      let_it_be(:project_isolated) { create(:project, organization: isolated_organization) }
      let_it_be(:project_other) { create(:project, organization: other_organization) }
      let_it_be(:runner_project_isolated) { create(:ci_runner_project, project: project_isolated) }
      let_it_be(:runner_project_other) { create(:ci_runner_project, project: project_other) }

      it 'scopes through ci_project_mirrors' do
        sql = Ci::RunnerProject.all.to_sql

        expect(sql).to include('FROM "ci_project_mirrors"')
        expect(sql).not_to include('FROM "projects"')
        expect(Ci::RunnerProject.all).to contain_exactly(runner_project_isolated)
      end
    end

    context 'when sharded by namespace_id' do
      let_it_be(:group_isolated) { create(:group, organization: isolated_organization) }
      let_it_be(:group_other) { create(:group, organization: other_organization) }
      let_it_be(:runner_namespace_isolated) { create(:ci_runner_namespace, group: group_isolated) }
      let_it_be(:runner_namespace_other) { create(:ci_runner_namespace, group: group_other) }

      it 'scopes through ci_namespace_mirrors' do
        sql = Ci::RunnerNamespace.all.to_sql

        expect(sql).to include('FROM "ci_namespace_mirrors"')
        expect(sql).not_to include('FROM "namespaces"')
        expect(Ci::RunnerNamespace.all).to contain_exactly(runner_namespace_isolated)
      end
    end
  end
end
