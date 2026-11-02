# frozen_string_literal: true

require 'rubocop_spec_helper'
require_relative '../../../../../rubocop/cop/gitlab/authz/use_granular_token_directive'

RSpec.describe RuboCop::Cop::Gitlab::Authz::UseGranularTokenDirective, feature_category: :permissions do
  it 'flags a check through the service in a mutation' do
    expect_offense(<<~RUBY)
      def resolve(project_path:)
        response = ::Authz::Tokens::AuthorizeGranularScopesService.new(
                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not check granular token permissions with `Authz::Tokens::AuthorizeGranularScopesService` in GraphQL code. Declare them with `authorize_granular_token`, so the docs and `gitlab:permissions:validate` see them. See https://docs.gitlab.com/development/permissions/granular_access/graphql_implementation_guide/#step-5-add-authorization-directives-to-types-and-mutations
          boundaries: [::Authz::Boundary.for(project)],
          permissions: :update_issue,
          token: context[:access_token]
        ).execute
      end
    RUBY
  end

  it 'flags the service without the leading double colon' do
    expect_offense(<<~RUBY)
      Authz::Tokens::AuthorizeGranularScopesService.new(boundaries: boundaries, permissions: permissions, token: token)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not check granular token permissions [...]
    RUBY
  end

  it 'flags the service when it is assigned to a constant' do
    expect_offense(<<~RUBY)
      SERVICE = ::Authz::Tokens::AuthorizeGranularScopesService
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not check granular token permissions [...]
    RUBY
  end

  it 'does not flag the authorize_granular_token directive' do
    expect_no_offenses(<<~RUBY)
      authorize_granular_token permissions: :update_issue, boundary_argument: :project_path, boundary_type: :project
    RUBY
  end

  it 'does not flag other services in the Authz::Tokens namespace' do
    expect_no_offenses(<<~RUBY)
      ::Authz::Tokens::PrivilegeEscalationCheck.new(granular_scopes, calling_token).execute
    RUBY
  end

  it 'does not flag a class of the same name in another namespace' do
    expect_no_offenses(<<~RUBY)
      ::Other::Tokens::AuthorizeGranularScopesService.new
    RUBY
  end
end
