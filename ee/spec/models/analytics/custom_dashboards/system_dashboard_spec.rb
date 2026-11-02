# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::CustomDashboards::SystemDashboard, feature_category: :custom_dashboards_foundation do
  let(:config) do
    {
      'title' => 'GitLab Duo and SDLC trends',
      'description' => 'Visualize Duo usage and development trends.',
      'version' => '2',
      'panels' => []
    }
  end

  subject(:dashboard) { described_class.new(slug: 'gitlab_duo', config: config) }

  describe '#id' do
    it 'returns a prefixed slug' do
      expect(dashboard.id).to eq('gitlab:dashboard:gitlab_duo')
    end
  end

  describe '#name' do
    it 'returns the title from config' do
      expect(dashboard.name).to eq('GitLab Duo and SDLC trends')
    end

    context 'when the config has no title' do
      let(:config) { { 'version' => '2', 'panels' => [] } }

      it 'falls back to the slug so the GraphQL name field stays non-null' do
        expect(dashboard.name).to eq('gitlab_duo')
      end
    end
  end

  describe '#errors' do
    it 'defaults to an empty list' do
      expect(dashboard.errors).to eq([])
    end

    it 'returns the schema errors it was built with' do
      invalid = described_class.new(slug: 'broken', config: {}, errors: ['root is missing required keys: title'])

      expect(invalid.errors).to eq(['root is missing required keys: title'])
    end
  end

  describe '#description' do
    it 'returns the description from config' do
      expect(dashboard.description).to eq('Visualize Duo usage and development trends.')
    end

    context 'when description is not present in config' do
      let(:config) { { 'title' => 'Test', 'version' => '2', 'panels' => [] } }

      it 'returns nil' do
        expect(dashboard.description).to be_nil
      end
    end
  end

  describe '#constraints' do
    it 'returns an empty hash when the config declares none' do
      expect(dashboard.constraints).to eq({})
    end

    context 'when the config declares constraints' do
      let(:config) { super().merge('constraints' => { 'feature_flag' => 'dap_impact_v1' }) }

      it 'returns them' do
        expect(dashboard.constraints).to eq({ 'feature_flag' => 'dap_impact_v1' })
      end
    end

    context 'when constraints is not a mapping' do
      using RSpec::Parameterized::TableSyntax

      let(:config) { { 'title' => 'Test', 'version' => '2', 'panels' => [], 'constraints' => value } }

      where(:value) { ['clickhouse', false, nil] }

      with_them do
        it 'returns the value as declared, for the policy to reject' do
          expect(dashboard.constraints).to eq(value)
        end
      end
    end
  end

  describe '#system?' do
    it 'returns true' do
      expect(dashboard.system?).to be(true)
    end
  end

  describe '#readonly?' do
    it 'returns true' do
      expect(dashboard.readonly?).to be(true)
    end
  end

  describe '#persisted?' do
    it 'returns true' do
      expect(dashboard.persisted?).to be(true)
    end
  end

  describe '#created_at' do
    it 'returns nil' do
      expect(dashboard.created_at).to be_nil
    end
  end
end
