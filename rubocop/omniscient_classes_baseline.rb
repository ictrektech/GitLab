# frozen_string_literal: true

require 'rubocop'
require 'yaml'
require 'fileutils'
require_relative 'cop/gitlab/omniscient_class_methods'

module RuboCop
  # Adds classes protected by Gitlab/OmniscientClassMethods to its baseline.
  # Only classes without a baseline directory are added. Existing classes are never
  # changed, so new methods cannot slip into their legacy methods.
  class OmniscientClassesBaseline
    Error = Class.new(StandardError)

    COP = Cop::Gitlab::OmniscientClassMethods
    INTRINSIC_HEADER = <<~YAML.freeze
      # Methods that are fundamental to the identity of %{class_name}. They stay in the class.
      # A method enters this list only when it moves from legacy_methods.yml after
      # agreement with the domain owners. Changes need CODEOWNERS approval.
      # Checked by Gitlab/OmniscientClassMethods. Class methods have a `self.` prefix.
      # See #{COP::DOC_LINK}
    YAML
    LEGACY_HEADER = <<~YAML.freeze
      # Methods of %{class_name} that existed before Gitlab/OmniscientClassMethods.
      # Move them to the bounded context where they belong and remove them from this
      # list. Do not add new methods. Class methods have a `self.` prefix.
      # See #{COP::DOC_LINK}
    YAML

    def initialize(paths:, baseline_dir:, root:, output: $stdout)
      @paths = paths
      @baseline_dir = baseline_dir
      @root = root
      @output = output
    end

    def add_missing_classes
      added = paths.filter_map do |path|
        class_name = class_name_for(path)
        directory = File.join(baseline_dir, COP.directory_name(class_name))
        next if Dir.exist?(directory)

        methods = method_names_for(path, class_name).sort
        write(directory, 'intrinsic_methods.yml', INTRINSIC_HEADER, class_name, [])
        write(directory, 'legacy_methods.yml', LEGACY_HEADER, class_name, methods)
        output.puts "Added #{class_name} with #{methods.size} legacy methods to #{directory.delete_prefix("#{root}/")}."
        class_name
      end

      output.puts 'Baseline is up to date.' if added.empty?
    end

    private

    attr_reader :paths, :baseline_dir, :root, :output

    # Follows the Zeitwerk convention: app/models/organizations/organization.rb
    # defines Organizations::Organization and ee/app/models/ee/project.rb defines EE::Project.
    # A domains/<name>/ prefix does not change the constant: domains/ci/app/models/ci/build.rb defines Ci::Build.
    def class_name_for(path)
      path.sub(%r{\A(domains/[^/]+/)?(ee/)?app/models/}, '').delete_suffix('.rb').split('/').map do |segment|
        segment == 'ee' ? 'EE' : segment.split('_').map(&:capitalize).join
      end.join('::')
    end

    def method_names_for(path, class_name)
      source = ProcessedSource.new(File.read(File.join(root, path)), RUBY_VERSION.to_f, path)
      methods = source.ast && COP.method_names_by_class(source.ast)[class_name]
      raise Error, "#{path} does not define methods for #{class_name}." unless methods

      methods
    end

    def write(directory, file_name, header, class_name, methods)
      FileUtils.mkdir_p(directory)
      content = format(header, class_name: class_name) + { class_name => methods }.to_yaml
      File.write(File.join(directory, file_name), content)
    end
  end
end
