# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Preloaders::UserMaxAccessLevelInProjectsPreloader, feature_category: :system_access do
  let_it_be(:user) { create(:user) }
  let_it_be(:project_1) { create(:project) }
  let_it_be(:project_2) { create(:project) }
  let_it_be(:project_3) { create(:project) }
  let_it_be(:project_4) { create(:project) }
  let_it_be(:project_5) { create(:project) }

  let(:projects) { [project_1, project_2, project_3, project_4, project_5] }
  let(:query) { projects.each { |project| user.can?(:read_project, project) } }

  before do
    project_1.add_developer(user)
    project_2.add_developer(user)
  end

  context 'without preloader' do
    before do
      stub_feature_flags(resolve_project_access_from_memberships: false)
    end

    it 'runs some queries', quarantine: 'https://gitlab.com/gitlab-org/gitlab/-/issues/444712' do
      # we have an existing N+1, one for each project for which user is not a member
      # in this spec, project_3, project_4, project_5
      # https://gitlab.com/gitlab-org/gitlab/-/issues/362890
      expect { query }.to make_queries(projects.size + 3)
    end
  end

  describe '#execute', :request_store do
    let(:projects_arg) { projects }

    context 'when user is present' do
      before do
        described_class.new(projects_arg, user).execute
      end

      it 'avoids N+1 queries', quarantine: 'https://gitlab.com/gitlab-org/quality/test-failure-issues/-/issues/25432' do
        expect { query }.not_to make_queries
      end

      context 'when projects is an array of IDs' do
        let(:projects_arg) { projects.map(&:id) }

        it 'avoids N+1 queries',
          quarantine: 'https://gitlab.com/gitlab-org/quality/test-failure-issues/-/issues/25432' do
          expect { query }.not_to make_queries
        end
      end

      # Test for handling of SQL table name clashes.
      context 'when projects is a relation including project_authorizations' do
        let(:projects_arg) do
          Project.where(id: ProjectAuthorization.where(project_id: projects).select(:project_id))
        end

        it 'avoids N+1 queries',
          quarantine: 'https://gitlab.com/gitlab-org/quality/test-failure-issues/-/issues/25432' do
          expect { query }.not_to make_queries
        end
      end
    end

    shared_examples 'stores the access level of every project' do
      it 'stores the access level of every project' do
        described_class.new(projects_arg, user).execute
        levels = nil

        expect { levels = projects.map { |project| project.team.max_member_access(user.id) } }
          .not_to exceed_query_limit(0)
        expect(levels).to eq([
          Gitlab::Access::DEVELOPER, Gitlab::Access::DEVELOPER,
          Gitlab::Access::NO_ACCESS, Gitlab::Access::NO_ACCESS, Gitlab::Access::NO_ACCESS
        ])
      end
    end

    shared_examples 'stores the access level of every project, whatever the input' do
      it_behaves_like 'stores the access level of every project'

      context 'when projects is an array of IDs' do
        let(:projects_arg) { projects.map(&:id) }

        it_behaves_like 'stores the access level of every project'
      end

      context 'when projects is a relation including project_authorizations' do
        let(:projects_arg) do
          Project.where(id: ProjectAuthorization.where(project_id: projects).select(:project_id))
            .or(Project.id_in(projects))
        end

        it_behaves_like 'stores the access level of every project'
      end
    end

    it_behaves_like 'stores the access level of every project, whatever the input'

    context 'when resolve_project_access_from_memberships is disabled' do
      before do
        stub_feature_flags(resolve_project_access_from_memberships: false)
      end

      it_behaves_like 'stores the access level of every project, whatever the input'
    end

    context 'when user is not present' do
      before do
        described_class.new(projects_arg, nil).execute
      end

      it 'does not avoid N+1 queries' do
        expect { query }.to make_queries
      end
    end
  end
end
