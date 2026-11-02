# frozen_string_literal: true

module RuboCop
  module Cop
    module Gitlab
      # Prevents adding methods to omniscient classes (also known as god classes),
      # such as `Project`, `Group`, `User` and their `EE::` counterparts.
      #
      # The cop loads, for each protected class or module, the methods it is allowed
      # to define from `config/omniscient_classes/<class_name>/`:
      #
      # - `intrinsic_methods.yml`: methods that are fundamental to the identity of the record.
      # - `legacy_methods.yml`: methods that existed before the cop and should move to
      #   the bounded context where they belong.
      #
      # Class methods are listed with a `self.` prefix. The cop also flags baseline
      # methods that the class no longer defines, so the baseline only shrinks.
      #
      # @example
      #
      #   # bad
      #   class Project < ApplicationRecord
      #     def merge_request_pipeline_stale?(pipeline)
      #       # ...
      #     end
      #   end
      #
      #   # good - define the behavior in the bounded context where it belongs
      #   module Ci
      #     class StalePipelineChecker
      #       def stale?(pipeline)
      #         # ...
      #       end
      #     end
      #   end
      class OmniscientClassMethods < RuboCop::Cop::Base
        BASELINE_DIR = 'rubocop/cop/gitlab/config/omniscient_classes'
        DOC_LINK = 'https://docs.gitlab.com/development/software_design/#taming-omniscient-classes'
        MSG = 'Do not add methods to omniscient classes like `%{class_name}`. ' \
          "Define the behavior in the bounded context where it belongs. See #{DOC_LINK}".freeze
        STALE_MSG = 'Remove methods that `%{class_name}` no longer defines from %{directory}: %{methods}'

        class << self
          def external_dependency_checksum
            @external_dependency_checksum ||= Digest::SHA256.hexdigest(
              baseline_files.map { |file| "#{file.delete_prefix(baseline_dir)}:#{Digest::SHA256.file(file)}" }.join
            )
          end

          def baseline
            @baseline ||= baseline_files.each_with_object({}) do |file, result|
              YAML.load_file(file).each { |class_name, methods| (result[class_name] ||= Set.new).merge(methods) }
            end
          end

          def baseline_files
            Dir[File.join(baseline_dir, '*', '{intrinsic,legacy}_methods.yml')]
          end

          def baseline_dir
            File.expand_path("../../../#{BASELINE_DIR}", __dir__)
          end

          # EE::Ci::Pipeline => ee_ci_pipeline
          def directory_name(class_name)
            class_name.split('::').map { |part| part.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase }.join('_')
          end

          # Returns the methods defined in the AST, keyed by owning class or module:
          # { 'Project' => ['foo', 'self.bar'] }
          def method_names_by_class(ast)
            ast.each_node(:def, :defs)
              .filter_map { |node| owner_and_method_name(node) }
              .group_by { |owner_node, _| qualified_name(owner_node) }
              .transform_values { |pairs| pairs.map(&:last).uniq }
          end

          # Returns the class or module that defines the method, and the method name.
          # Class methods (`def self.x`, `class << self` or `class_methods do`) get a `self.` prefix.
          def owner_and_method_name(node)
            return if node.defs_type? && !node.receiver.self_type?

            singleton = node.defs_type?
            owner = node.each_ancestor.find do |ancestor|
              singleton ||= ancestor.sclass_type? || (ancestor.block_type? && ancestor.method?(:class_methods))
              ancestor.type?(:class, :module)
            end
            return unless owner

            [owner, singleton ? "self.#{node.method_name}" : node.method_name.to_s]
          end

          def qualified_name(node)
            [node, *node.each_ancestor(:class, :module)].reverse.map { |n| n.identifier.const_name }.join('::')
          end
        end

        def on_new_investigation
          super
          @defined_methods = Hash.new { |h, k| h[k] = Set.new }
          @owner_nodes = {}
        end

        def on_def(node)
          check(node)
        end

        alias_method :on_defs, :on_def

        def on_investigation_end
          super

          @owner_nodes.each do |class_name, owner_node|
            stale = self.class.baseline[class_name] - @defined_methods[class_name]
            next if stale.empty?

            add_offense(owner_node.identifier, message: format(STALE_MSG, class_name: class_name,
              directory: "#{BASELINE_DIR}/#{self.class.directory_name(class_name)}/", methods: stale.sort.join(', ')))
          end
        end

        def external_dependency_checksum
          self.class.external_dependency_checksum
        end

        private

        def check(node)
          owner_node, method_name = self.class.owner_and_method_name(node)
          return unless owner_node

          class_name = self.class.qualified_name(owner_node)
          allowed = self.class.baseline[class_name]
          return unless allowed

          @owner_nodes[class_name] ||= owner_node
          @defined_methods[class_name] << method_name

          add_offense(node.loc.name, message: format(MSG, class_name: class_name)) unless allowed.include?(method_name)
        end
      end
    end
  end
end
