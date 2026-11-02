# frozen_string_literal: true

# Covers the GraphQL link between a Duo Agent Platform session and one artifact type
# from both directions: artifact -> `duoWorkflowLinks` -> session -> `<artifact>Links`.
#
# The host spec defines:
#   let_it_be :project, :public_project, :user (developer of project), :workflow (owned by user)
#   let_it_be :source_artifact, :other_artifact (two artifacts in project)
#   def create_artifact(project) - builds one more artifact in the given project
#
# Artifacts that are not a top-level query field (for example pipelines) override
# `artifact_query`, `artifact_data_path` and `artifact_read_permissions` in the block.
RSpec.shared_examples 'a GraphQL API for Duo Agent Platform session links' do |
  artifact:, source_link_type: :source, other_link_type: :created
  |
  link_factory = :"duo_workflows_workflow_#{artifact}"
  link_model = "::Ai::DuoWorkflows::Workflow#{artifact.to_s.camelize}".constantize
  artifact_label = artifact.to_s.humanize(capitalize: false)
  unused_link_type = (link_model.link_types.keys.map(&:to_sym) - [source_link_type]).first

  let_it_be(:source_link) do
    create(link_factory, workflow: workflow, artifact => source_artifact, link_type: source_link_type)
  end

  let_it_be(:other_link) do
    create(link_factory, workflow: workflow, artifact => other_artifact, link_type: other_link_type)
  end

  let(:current_user) { user }
  let(:artifact_field) { artifact.to_s.camelize(:lower) }
  let(:links_field) { "#{artifact_field}Links" }
  let(:artifact_data_path) { [artifact] }
  let(:artifact_read_permissions) { [:"read_#{artifact}"] }

  let(:source_node) do
    { 'linkType' => source_link_type.to_s.upcase, artifact_field => { 'id' => source_artifact.to_gid.to_s } }
  end

  let(:other_node) do
    { 'linkType' => other_link_type.to_s.upcase, artifact_field => { 'id' => other_artifact.to_gid.to_s } }
  end

  before do
    # Make read_duo_workflow pass for the workflow owner, matching WorkflowPolicy's
    # owner rule. The link type delegates to the workflow for the same ability.
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    allow_any_instance_of(User).to receive(:allowed_to_use?).and_return(true) # rubocop:disable RSpec/AnyInstanceOf -- current_user identity differs across the request
  end

  def artifact_query(record, selection)
    %(#{artifact_field}(id: "#{record.to_gid}") { #{selection} })
  end

  def links_query(record, selection)
    "query { #{artifact_query(record, selection)} }"
  end

  def session_links_selection(filter = nil)
    <<~GRAPHQL
      duoWorkflowLinks {
        nodes {
          linkType
          workflow {
            id
            #{links_field}#{filter && "(linkType: #{filter.to_s.upcase})"} {
              nodes {
                linkType
                #{artifact_field} { id }
              }
            }
          }
        }
      }
    GRAPHQL
  end

  def artifact_links
    graphql_data_at(*artifact_data_path, :duo_workflow_links, :nodes)
  end

  def session_links
    artifact_links.first.dig('workflow', links_field, 'nodes')
  end

  context "when querying a #{artifact_label} for its sessions and their #{artifact_label.pluralize}" do
    let(:query) { links_query(source_artifact, session_links_selection) }

    it "traverses #{artifact_label} -> sessions -> #{artifact_label.pluralize}" do
      post_graphql(query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(graphql_errors).to be_nil

      expect(artifact_links.pluck('linkType')).to contain_exactly(source_link_type.to_s.upcase)
      expect(artifact_links.first.dig('workflow', 'id')).to eq(workflow.to_gid.to_s)
      expect(session_links).to contain_exactly(source_node, other_node)
    end
  end

  context 'with a link_type filter on the session links' do
    let(:query) { links_query(source_artifact, session_links_selection(other_link_type)) }

    it 'returns only links of the requested type' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil

      expected = [source_node, other_node].select { |node| node['linkType'] == other_link_type.to_s.upcase }
      expect(session_links).to match_array(expected)
    end
  end

  if unused_link_type
    context 'with a link_type filter that matches no links' do
      let_it_be(:lonely_artifact) { create_artifact(project) }
      let_it_be(:lonely_workflow) { create(:duo_workflows_workflow, project: project, user: user) }

      let_it_be(:lonely_link) do
        create(link_factory, workflow: lonely_workflow, artifact => lonely_artifact, link_type: source_link_type)
      end

      let(:query) { links_query(lonely_artifact, session_links_selection(unused_link_type)) }

      it 'returns an empty list of links' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(session_links).to be_empty
      end
    end
  end

  context "when the #{artifact_label} has no linked sessions" do
    let_it_be(:lonely_artifact) { create_artifact(project) }

    let(:query) { links_query(lonely_artifact, 'duoWorkflowLinks { nodes { linkType } }') }

    it 'returns an empty list of links' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(artifact_links).to be_empty
    end
  end

  context 'with multiple linked sessions' do
    let(:query) do
      links_query(source_artifact, 'duoWorkflowLinks { nodes { linkType workflow { id humanStatus } } }')
    end

    it 'does not N+1 on the per-session authorization' do
      post_graphql(query, current_user: current_user) # warm up one-time setup queries
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }
      expect(graphql_errors).to be_nil

      # Another session, owned by the same user, also linked to the source artifact.
      other_workflow = create(:duo_workflows_workflow, project: project, user: user)
      create(link_factory, workflow: other_workflow, artifact => source_artifact, link_type: source_link_type)

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
      expect(artifact_links.count).to eq(2)
    end
  end

  context "with multiple #{artifact_label.pluralize} linked to the session" do
    let(:query) { links_query(source_artifact, session_links_selection) }

    it "does not N+1 on the linked #{artifact_label.pluralize}" do
      post_graphql(query, current_user: current_user) # warm up one-time setup queries
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }
      expect(graphql_errors).to be_nil

      extra_artifact = create_artifact(project)
      create(link_factory, workflow: workflow, artifact => extra_artifact, link_type: other_link_type)

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
    end
  end

  context 'with a granular personal access token' do
    # The traversal crosses two granular boundaries: the artifact type authorizes its
    # own read permission at the :project boundary, and the link type authorizes
    # `read_duo_workflow` at the :user boundary.
    let(:read_artifact_scope) do
      build(:granular_scope, boundary: ::Authz::Boundary.for(project),
        permissions: artifact_read_permissions.map { |permission| assignable_name(permission) })
    end

    let(:read_duo_workflow_scope) do
      build(:granular_scope, boundary: ::Authz::Boundary.for(:user), organization: project.organization,
        permissions: [assignable_name(:read_duo_workflow)])
    end

    let(:token_scopes) { [read_artifact_scope, read_duo_workflow_scope] }

    let(:pat) do
      create(:granular_pat, user: user, organization: project.organization).tap do |token|
        token_scopes.each do |scope|
          create(:personal_access_token_granular_scope,
            personal_access_token: token, granular_scope: scope, organization: project.organization)
        end
      end
    end

    let(:query) { links_query(source_artifact, 'duoWorkflowLinks { nodes { linkType } }') }

    def assignable_name(permission)
      ::Authz::PermissionGroups::Assignable.for_permission(permission).first.name
    end

    it 'returns the linked sessions' do
      post_graphql(query, token: { personal_access_token: pat })

      expect(graphql_errors).to be_nil
      expect(artifact_links.pluck('linkType')).to contain_exactly(source_link_type.to_s.upcase)
    end

    context 'when the token is missing the read_duo_workflow scope' do
      let(:token_scopes) { [read_artifact_scope] }

      it "reads the #{artifact_label} but omits its session links" do
        post_graphql(query, token: { personal_access_token: pat })

        expect(graphql_errors).to be_nil
        expect(graphql_data_at(*artifact_data_path)).to be_present
        expect(artifact_links).to be_empty
      end
    end

    context 'when the `granular_personal_access_tokens` feature flag is disabled' do
      before do
        stub_feature_flags(granular_personal_access_tokens: false)
      end

      it 'denies access' do
        post_graphql(query, token: { personal_access_token: pat })

        expect(graphql_data_at(artifact_data_path.first)).to be_nil
      end
    end
  end

  describe 'granular personal access token authorization' do
    # A public project lets the token pass the parent artifact authorization via the
    # public-access bypass, so the test gates on the link type's `read_duo_workflow`
    # permission at the user boundary.
    let_it_be(:public_artifact) { create_artifact(public_project) }
    let_it_be(:public_workflow) { create(:duo_workflows_workflow, project: public_project, user: user) }

    let_it_be(:public_link) do
      create(link_factory, workflow: public_workflow, artifact => public_artifact, link_type: source_link_type)
    end

    let(:query) { links_query(public_artifact, 'duoWorkflowLinks { nodes { linkType } }') }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(public_project, :duo_workflow).and_return(true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_duo_workflow do
      let(:boundary_object) { :user }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    end
  end

  context 'when the user cannot read the linked session' do
    let_it_be(:other_user) { create(:user, developer_of: project) }
    let(:current_user) { other_user }

    let(:query) { links_query(source_artifact, 'duoWorkflowLinks { nodes { linkType } }') }

    it "omits the link from the #{artifact_label}" do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(artifact_links).to be_empty
    end
  end

  context "when the #{artifact_label} is linked to sessions the user cannot all read" do
    let_it_be(:other_user) { create(:user, developer_of: project) }
    let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: project, user: other_user) }

    let_it_be(:redacted_link) do
      create(link_factory, workflow: other_workflow, artifact => source_artifact, link_type: source_link_type)
    end

    let(:query) { links_query(source_artifact, 'duoWorkflowLinks { nodes { linkType workflow { id } } }') }

    it 'returns only the links to sessions the user can read' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil

      linked_workflows = artifact_links.map { |node| node.dig('workflow', 'id') }
      expect(linked_workflows).to contain_exactly(workflow.to_gid.to_s)
    end
  end
end
