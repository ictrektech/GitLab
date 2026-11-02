# frozen_string_literal: true

require 'spec_helper'
require 'parser/current'

RSpec.describe Banzai::ReferenceResolver, feature_category: :markdown do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:other_organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:project) { create(:project, group: group, organization: organization) }
  let_it_be(:other_group) { create(:group, organization: other_organization) }
  let_it_be(:other_project) { create(:project, group: other_group, organization: other_organization) }
  let_it_be(:other_user) { create(:user, organization: other_organization) }

  subject(:resolver) { described_class.new(project: project) }

  describe '.from_context' do
    it 'derives the organization from the project in a filter context' do
      expect(described_class.from_context(project: project).organization).to eq(organization)
    end
  end

  describe '#organization' do
    it 'is the organization of the project' do
      expect(resolver.organization).to eq(organization)
    end

    it 'is the organization of the group when there is no project' do
      expect(described_class.new(group: other_group).organization).to eq(other_organization)
    end

    it 'is the first organization of the author when there is neither' do
      expect(described_class.new(author: other_user).organization).to eq(other_organization)
    end

    it 'falls back to the first organization on the instance' do
      expect(described_class.new.organization).to eq(Organizations::Organization.order(:id).first)
    end
  end

  describe 'relations' do
    it 'answers projects from every organization' do
      expect(resolver.projects).to include(project, other_project)
    end

    it 'answers namespaces from every organization' do
      expect(resolver.namespaces).to include(group, other_group)
    end

    it 'answers groups from every organization' do
      expect(resolver.groups).to include(group, other_group)
    end

    it 'answers users from every organization' do
      expect(resolver.users).to include(other_user)
    end

    it 'answers routes for paths from every organization' do
      routes = resolver.routes_by_paths([project.full_path, other_project.full_path])

      expect(routes.map(&:source)).to contain_exactly(project, other_project)
    end

    it 'answers organization user details from its own organization only' do
      own_detail = create(:organization_user_detail, organization: organization)
      create(:organization_user_detail, organization: other_organization)

      expect(resolver.organization_user_details).to contain_exactly(own_detail)
    end
  end

  describe '#request_store_key' do
    it 'extends a key with the cache key' do
      expect(resolver.request_store_key(:banzai_collection_cache)).to eq([:banzai_collection_cache, nil])
    end
  end

  describe 'container lookups in the reference machinery' do
    def guarded_files
      resolver = Rails.root.join('lib/banzai/reference_resolver.rb').to_s

      Rails.root.glob('{,ee/}lib/{,ee/}banzai/**/*.rb').map(&:to_s) - [resolver]
    end

    def container_constants
      %i[Project Namespace Group Route User]
    end

    def allowed_receiver_methods
      %i[
        reference_pattern link_reference_pattern markdown_reference_pattern
        reference_prefix reference_postfix reference_postfix_escaped reference_valid?
      ]
    end

    def allowed_argument_methods
      %i[is_a? kind_of? instance_of? object_class= ===]
    end

    def bare_lookups(source, path)
      offences = []
      walk(Parser::CurrentRuby.parse(source), nil, path, offences)
      offences
    end

    def walk(node, parent, path, offences)
      return unless node.is_a?(Parser::AST::Node)

      offences << "#{path}:#{node.loc.line}" if container_lookup?(node, parent)
      node.children.each { |child| walk(child, node, path, offences) }
    end

    def container_lookup?(node, parent)
      return false unless node.type == :const

      scope, name = *node
      return false unless container_constants.include?(name)
      return false unless scope.nil? || scope.type == :cbase

      !permitted_use?(node, parent)
    end

    def permitted_use?(node, parent)
      case parent&.type
      when :send
        receiver, method_name, *arguments = *parent

        (receiver.equal?(node) && allowed_receiver_methods.include?(method_name)) ||
          (arguments.any? { |argument| argument.equal?(node) } && allowed_argument_methods.include?(method_name))
      when :when, :array, :const
        true
      else
        false
      end
    end

    it 'reports a lookup through a container constant, scoped or not' do
      source = <<~SOURCE
        class Example
          def call(path, username)
            Project.find_by_full_path(path)
            ::User.find_by(username: username)
          end
        end
      SOURCE

      expect(bare_lookups(source, 'example.rb')).to eq(%w[example.rb:3 example.rb:4])
    end

    it 'permits type checks, reference patterns, case branches, arrays and constant scopes' do
      source = <<~SOURCE
        class Example
          def call(object, text)
            case object
            when Project then Project.reference_pattern.match?(text)
            when Group, Namespace then [Project, Group].include?(object.class)
            else object.is_a?(User) && User::MAXIMUM_USERNAME_LENGTH
            end
          end
        end
      SOURCE

      expect(bare_lookups(source, 'example.rb')).to be_empty
    end

    it 'covers the reference machinery' do
      paths = %w[
        lib/banzai/reference_parser/base_parser.rb
        lib/banzai/filter/references/user_reference_filter.rb
        lib/banzai/filter/reference_redactor_filter.rb
        lib/banzai/filter/commit_trailers_filter.rb
      ]
      paths << 'ee/lib/ee/banzai/filter/references/epic_reference_filter.rb' if Gitlab.ee?

      expect(guarded_files).to include(*paths.map { |path| Rails.root.join(path).to_s })
    end

    it 'all go through the resolver' do
      expect(guarded_files.flat_map { |path| bare_lookups(File.read(path), path) }).to be_empty
    end
  end
end
