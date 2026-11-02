# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::SecurityUpdate::MergeRequestTitle,
  feature_category: :dependency_management do
  using RSpec::Parameterized::TableSyntax

  def dependency(name:, version:, previous_version: '1.0.0')
    DependencyManagement::SecurityUpdate::OutputParser::DependencyChange.new(
      name: name, previous_version: previous_version, version: version
    )
  end

  describe '.build' do
    it 'renders a single-dependency title' do
      title = described_class.build([dependency(name: 'rails', previous_version: '6.1.4', version: '6.1.5')])

      expect(title).to eq('Security: Update rails from 6.1.4 to 6.1.5')
    end

    it 'renders a grouped title for multiple dependencies' do
      deps = [dependency(name: 'rails', version: '6.1.5'), dependency(name: 'rack', version: '3.0.0')]

      expect(described_class.build(deps)).to eq('Security: Update 2 dependencies')
    end

    context 'with a conventional commit style' do
      let(:style) { DependencyManagement::SecurityUpdate::CommitConvention::Style.new(type: 'chore', capitalize: false) }

      it 'renders a conventional single-dependency title' do
        title = described_class.build(
          [dependency(name: 'rails', previous_version: '6.1.4', version: '6.1.5')], style: style
        )

        expect(title).to eq('chore(deps): [security] update rails from 6.1.4 to 6.1.5')
      end

      it 'renders a conventional grouped title' do
        deps = [dependency(name: 'rails', version: '6.1.5'), dependency(name: 'rack', version: '3.0.0')]

        expect(described_class.build(deps, style: style)).to eq('chore(deps): [security] update 2 dependencies')
      end

      it 'capitalises the subject when the repository does' do
        style.capitalize = true

        title = described_class.build([dependency(name: 'rails', version: '6.1.5')], style: style)

        expect(title).to start_with('chore(deps): [Security] Update rails')
      end

      it 'drops the previous version when the header would exceed 100 characters' do
        name = "com.example.#{'a' * 35}:artifact"
        title = described_class.build(
          [dependency(name: name, previous_version: '1.2.3', version: '1.2.4')], style: style
        )

        expect(title).to eq("chore(deps): [security] update #{name} to 1.2.4")
        expect(title.length).to be <= 100
      end

      it 'keeps the full name when even the short form exceeds 100 characters' do
        name = 'org.springframework.cloud:spring-cloud-starter-netflix-eureka-client'

        title = described_class.build([dependency(name: name, version: '4.1.3')], style: style)

        expect(title).to eq("chore(deps): [security] update #{name} to 4.1.3")
        expect(title.length).to be > 100
      end
    end
  end

  describe '.parse_single_dependency' do
    it 'captures the name and target version' do
      match = described_class.parse_single_dependency('Security: Update rails from 6.1.4 to 6.1.5')

      expect(match[:name]).to eq('rails')
      expect(match[:version]).to eq('6.1.5')
    end

    where(:title, :name, :version) do
      'chore(deps): [security] update rails from 6.1.4 to 6.1.5' | 'rails' | '6.1.5'
      'build(deps): [Security] Update @scope/pkg from 1.0 to 2.0' | '@scope/pkg' | '2.0'
      'chore(deps): [security] update com.example:artifact to 1.2.4' | 'com.example:artifact' | '1.2.4'
    end

    with_them do
      it 'captures the name and target version of a conventional title' do
        match = described_class.parse_single_dependency(title)

        expect(match[:name]).to eq(name)
        expect(match[:version]).to eq(version)
      end
    end

    it 'does not match grouped titles' do
      expect(described_class.parse_single_dependency('Security: Update 2 dependencies')).to be_nil
      expect(described_class.parse_single_dependency('chore(deps): [security] update 2 dependencies')).to be_nil
    end
  end

  describe 'round trip' do
    plain = nil
    lower = DependencyManagement::SecurityUpdate::CommitConvention::Style.new(type: 'build', capitalize: false)
    upper = DependencyManagement::SecurityUpdate::CommitConvention::Style.new(type: 'Chore', capitalize: true)
    long_name = 'org.springframework.cloud:spring-cloud-starter-netflix-eureka-client'

    where(:style, :name) do
      plain | '@scope/pkg'
      lower | '@scope/pkg'
      upper | '@scope/pkg'
      lower | long_name
    end

    with_them do
      it 'parses back the title built for a single dependency' do
        dep = dependency(name: name, previous_version: '1.2.3', version: '4.5.6')

        match = described_class.parse_single_dependency(described_class.build([dep], style: style))

        expect(match[:name]).to eq(name)
        expect(match[:version]).to eq('4.5.6')
      end
    end
  end
end
