# frozen_string_literal: true

# Requires:
# - `artifact_field`: the GraphQL name of the artifact field, for example `mergeRequest`.
# - `link_type_enum`: the GraphQL name of the reused `linkType` enum.
# - `readable_link` and `unreadable_link`: links whose artifact the `compliance_user` can and can't read.
# All links belong to a chat workflow, which the `compliance_user` can't read with `read_duo_workflow`.
RSpec.shared_examples 'an AI governance session link type' do
  include GraphqlHelpers
  include Graphql::ResolverFactories

  it 'exposes the expected fields without a workflow field' do
    expect(described_class).to have_graphql_fields(:id, :created_at, :link_type, artifact_field)
  end

  it 'reuses the link type enum' do
    expect(described_class.fields['linkType'].type.to_type_signature).to eq("#{link_type_enum}!")
  end

  it 'has no type-level authorization' do
    expect(described_class.authorization).to be_none
  end

  it 'skips granular token authorization because the parent authorizes' do
    directive = described_class.directives.find { |d| d.is_a?(Directives::Authz::GranularScope) }

    expect(directive.arguments[:skip_reason]).to eq('parent_authorizes')
  end

  describe 'resolving a link for a user with read_agent_artifacts but not read_duo_workflow' do
    let(:link) { readable_link }
    let(:user) { compliance_user }
    let(:query_string) { "{ link { id linkType #{artifact_field} { id } } }" }
    let(:link_type) { described_class }
    let(:query_type) do
      resolver = new_resolver(link)
      type = link_type
      query_factory { |query| query.field :link, type, null: true, resolver: resolver }
    end

    subject(:result) { execute_query(query_type).to_h }

    before do
      stub_licensed_features(custom_roles: true, group_level_compliance_dashboard: true)
    end

    it 'has the expected permissions', :aggregate_failures do
      expect(user.can?(:read_agent_artifacts, link.workflow.project.group)).to be(true)
      expect(user.can?(:read_duo_workflow, link.workflow)).to be(false)
    end

    it 'resolves the link and its artifact', :aggregate_failures do
      expect(result['errors']).to be_nil
      expect(result.dig('data', 'link')).to include(
        'id' => link.to_global_id.to_s,
        'linkType' => link.link_type.upcase,
        artifact_field => { 'id' => readable_artifact_gid }
      )
    end

    context 'when the user cannot read the artifact' do
      let(:link) { unreadable_link }

      it 'resolves the link with a null artifact', :aggregate_failures do
        expect(result['errors']).to be_nil
        expect(result.dig('data', 'link')).to include('id' => link.to_global_id.to_s, artifact_field => nil)
      end
    end
  end
end

RSpec.shared_context 'with AI governance session links for a compliance user' do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :public, group: group) }
  let_it_be(:private_project) { create(:project, :private) }
  let_it_be(:compliance_user) { create(:user) }
  let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
  let_it_be(:membership) do
    create(:group_member, :guest, member_role: member_role, user: compliance_user, group: group)
  end

  let_it_be(:workflow) { create(:duo_workflows_workflow, :agentic_chat, project: project) }
end
