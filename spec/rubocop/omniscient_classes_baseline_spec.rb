# frozen_string_literal: true

require 'fast_spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../rubocop/omniscient_classes_baseline'

RSpec.describe RuboCop::OmniscientClassesBaseline, feature_category: :tooling do
  let(:root) { Dir.mktmpdir }
  let(:baseline_dir) { File.join(root, 'baseline') }
  let(:output) { StringIO.new }
  let(:paths) { ['app/models/project.rb', 'app/models/organizations/organization.rb', 'ee/app/models/ee/project.rb'] }

  subject(:add_missing_classes) do
    described_class.new(paths: paths, baseline_dir: baseline_dir, root: root, output: output).add_missing_classes
  end

  before do
    write_file('baseline/project/legacy_methods.yml', "Project:\n- existing_method\n")
    write_file('app/models/project.rb', "class Project\n  def existing_method; end\n  def new_method; end\nend\n")
    write_file('app/models/organizations/organization.rb', <<~RUBY)
      module Organizations
        class Organization
          def self.find_by_path; end
          def b_method; end
          def a_method; end
        end
      end
    RUBY
    write_file('ee/app/models/ee/project.rb', <<~RUBY)
      module EE
        module Project
          module FilterByBranch
            def nested_method; end
          end

          class_methods do
            def ee_class_method; end
          end

          def ee_method; end
        end
      end
    RUBY
  end

  after do
    FileUtils.rm_rf(root)
  end

  it 'writes the intrinsic and legacy files of missing classes' do
    add_missing_classes

    expect(YAML.load_file(File.join(baseline_dir, 'organizations_organization/intrinsic_methods.yml')))
      .to eq('Organizations::Organization' => [])
    expect(YAML.load_file(File.join(baseline_dir, 'organizations_organization/legacy_methods.yml')))
      .to eq('Organizations::Organization' => %w[a_method b_method self.find_by_path])
    expect(YAML.load_file(File.join(baseline_dir, 'ee_project/legacy_methods.yml')))
      .to eq('EE::Project' => %w[ee_method self.ee_class_method])
    expect(File.read(File.join(baseline_dir, 'ee_project/intrinsic_methods.yml')))
      .to start_with('# Methods that are fundamental to the identity of EE::Project.')
    expect(output.string).to eq(<<~OUTPUT)
      Added Organizations::Organization with 3 legacy methods to baseline/organizations_organization.
      Added EE::Project with 2 legacy methods to baseline/ee_project.
    OUTPUT
  end

  it 'does not change classes that already have a baseline directory' do
    expect { add_missing_classes }
      .not_to change { File.read(File.join(baseline_dir, 'project/legacy_methods.yml')) }
    expect(File).not_to exist(File.join(baseline_dir, 'project/intrinsic_methods.yml'))
  end

  context 'when all classes are in the baseline' do
    let(:paths) { ['app/models/project.rb'] }

    it 'reports that the baseline is up to date' do
      add_missing_classes

      expect(output.string).to eq("Baseline is up to date.\n")
    end
  end

  context 'when the class is defined under domains/' do
    let(:paths) { ['domains/ci/app/models/ci/build.rb', 'domains/ci/ee/app/models/ee/ci/build.rb'] }

    before do
      write_file('domains/ci/app/models/ci/build.rb', "module Ci\n  class Build\n    def ci_method; end\n  end\nend\n")
      write_file('domains/ci/ee/app/models/ee/ci/build.rb', <<~RUBY)
        module EE
          module Ci
            module Build
              def ee_ci_method; end
            end
          end
        end
      RUBY
    end

    it 'derives the class name without the domain prefix' do
      add_missing_classes

      expect(YAML.load_file(File.join(baseline_dir, 'ci_build/legacy_methods.yml')))
        .to eq('Ci::Build' => %w[ci_method])
      expect(YAML.load_file(File.join(baseline_dir, 'ee_ci_build/legacy_methods.yml')))
        .to eq('EE::Ci::Build' => %w[ee_ci_method])
    end
  end

  context 'when the file does not define the expected class' do
    let(:paths) { ['app/models/user.rb'] }

    before do
      write_file('app/models/user.rb', "class Member\n  def foo; end\nend\n")
    end

    it 'raises an error' do
      expect { add_missing_classes }
        .to raise_error(described_class::Error, 'app/models/user.rb does not define methods for User.')
    end
  end

  def write_file(path, content)
    full_path = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end
end
