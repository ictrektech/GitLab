# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::ModelMetadata, feature_category: :duo_agent_platform do
  let(:definitions) do
    {
      'models' => [
        { 'identifier' => 'claude_sonnet_4_5', 'name' => 'Claude Sonnet 4.5', 'provider' => 'Anthropic' },
        { 'identifier' => 'claude_haiku_4_5_20251001_bedrock', 'name' => 'Claude Haiku 4.5 - Bedrock',
          'provider' => 'Bedrock' },
        { 'identifier' => 'claude_haiku_4_5_20251001', 'name' => 'Claude Haiku 4.5 - Vertex',
          'provider' => 'Vertex' },
        { 'identifier' => 'gpt_5_mini', 'name' => 'GPT-5 mini', 'provider' => 'OpenAI' },
        { 'identifier' => 'claude_opus_4_6_bedrock', 'name' => 'Claude Opus 4.6 - Bedrock',
          'provider' => 'Bedrock' },
        { 'identifier' => 'claude_sonnet_4_6', 'name' => 'Claude Sonnet 4.6', 'provider' => 'Anthropic' },
        { 'identifier' => 'claude_sonnet_4_6_vertex', 'name' => 'Claude Sonnet 4.6',
          'provider' => 'Gemini Enterprise Agent Platform' },
        { 'identifier' => 'claude_sonnet_4_6_20260115_vertex', 'name' => 'Claude Sonnet 4.6',
          'provider' => 'Gemini Enterprise Agent Platform' },
        { 'identifier' => '__default__agentic_chat', 'name' => 'GitLab Default', 'provider' => 'GitLab' },
        { 'identifier' => 'twin_a', 'name' => 'Twin', 'provider' => 'ProviderA' },
        { 'identifier' => 'twin_b', 'name' => 'Twin', 'provider' => 'ProviderB' }
      ],
      'unit_primitives' => [
        # Two default models make the gateway emit the pseudo ref in the
        # singular field and the real refs in default_models.
        { 'feature_setting' => 'duo_agent_platform_agentic_chat',
          'default_model' => '__default__agentic_chat',
          'default_models' => %w[claude_haiku_4_5_20251001_bedrock claude_haiku_4_5_20251001] },
        { 'feature_setting' => 'duo_agent_platform', 'default_model' => 'claude_sonnet_4_5' }
      ]
    }
  end

  before do
    allow(::Ai::ModelSelection::ModelDefinitions).to receive(:fetch).and_return(
      ::Ai::ModelSelection::ModelDefinitions.new(ServiceResponse.success(payload: definitions))
    )
  end

  def entry_for(value)
    described_class.for([value]).fetch(value)
  end

  it 'matches an exact catalog ref and flags the workflow feature default' do
    entry = entry_for('claude_sonnet_4_5')

    expect(entry.to_h).to eq(
      id: 'claude_sonnet_4_5', model_key: 'claude_sonnet_4_5', name: 'Claude Sonnet 4.5', provider: 'Anthropic',
      hosting: :gitlab, is_default: true
    )
  end

  it 'flags every load-balanced chat default, not the pseudo ref alone' do
    expect(entry_for('claude_haiku_4_5_20251001_bedrock').is_default).to be(true)
    expect(entry_for('claude_haiku_4_5_20251001').is_default).to be(true)
  end

  it 'flags rows recorded as routed default traffic' do
    expect(entry_for('__default__agentic_chat').is_default).to be(true)
  end

  it 'matches a catalog display name' do
    entry = entry_for('GPT-5 mini')

    expect(entry.to_h).to eq(
      id: 'GPT-5 mini', model_key: 'gpt_5_mini', name: 'GPT-5 mini', provider: 'OpenAI', hosting: :gitlab,
      is_default: false
    )
  end

  it 'normalizes a provider-resolved id and prefers the Bedrock ref' do
    entry = entry_for('us.anthropic.claude-haiku-4-5-20251001-v1:0')

    expect(entry.to_h).to eq(
      id: 'us.anthropic.claude-haiku-4-5-20251001-v1:0',
      model_key: 'claude_haiku_4_5_20251001', # gitleaks:allow -- a model catalog ref, not a secret
      name: 'Claude Haiku 4.5', provider: 'Bedrock', hosting: :gitlab, is_default: true
    )
  end

  it 'keeps provider ambiguous for a bare resolved id shared by hosting twins' do
    entry = entry_for('claude-sonnet-4-6')

    expect(entry.name).to eq('Claude Sonnet 4.6')
    expect(entry.provider).to be_nil
  end

  it 'resolves the Vertex @date id form to the vertex ref' do
    entry = entry_for('claude-sonnet-4-6@20260115')

    expect(entry.name).to eq('Claude Sonnet 4.6')
    expect(entry.provider).to eq('Gemini Enterprise Agent Platform')
  end

  it 'resolves the @date form through the base ref when no vertex ref exists' do
    entry = entry_for('claude-haiku-4-5@20251001')

    expect(entry.provider).to eq('Vertex')
  end

  it 'resolves bedrock/ and global. id forms to the Bedrock ref' do
    ['bedrock/global.anthropic.claude-haiku-4-5-20251001-v1:0',
      'global.anthropic.claude-haiku-4-5-20251001-v1:0'].each do |raw|
      entry = entry_for(raw)

      expect(entry.name).to eq('Claude Haiku 4.5')
      expect(entry.provider).to eq('Bedrock')
    end
  end

  it 'resolves Bedrock version suffixes without a colon' do
    ['bedrock/global.anthropic.claude-opus-4-6-v1',
      'global.anthropic.claude-opus-4-6-v1'].each do |raw|
      entry = entry_for(raw)

      expect(entry.name).to eq('Claude Opus 4.6')
      expect(entry.provider).to eq('Bedrock')
    end
  end

  it 'keeps a bare version suffix on ids no host recognizes' do
    entry = entry_for('gpt-5-mini-v1')

    expect(entry.name).to eq('gpt-5-mini-v1')
    expect(entry.provider).to be_nil
  end

  it 'gives no provider to an ambiguous display name' do
    entry = entry_for('Twin')

    expect(entry.provider).to be_nil
    expect(entry.name).to eq('Twin')
  end

  it 'gives no provider to the routed default pseudo entry' do
    entry = entry_for('__default__agentic_chat')

    expect(entry.provider).to be_nil
    expect(entry.name).to eq('GitLab Default')
  end

  context 'when a single default has a hosting twin outside the default set' do
    before do
      definitions['unit_primitives'][0] = {
        'feature_setting' => 'duo_agent_platform_agentic_chat',
        'default_model' => 'claude_haiku_4_5_20251001'
      }
      definitions['unit_primitives'][1]['default_model'] = 'gpt_5_mini'
    end

    it 'flags the default model itself' do
      expect(entry_for('claude_haiku_4_5_20251001').is_default).to be(true)
    end

    it 'does not flag the hosting twin sharing the stripped display name' do
      entry = entry_for('claude_haiku_4_5_20251001_bedrock')

      expect(entry.name).to eq('Claude Haiku 4.5')
      expect(entry.is_default).to be(false)
    end
  end

  it 'falls back to the raw value when an id normalizes to nothing' do
    entry = entry_for('anthropic.')

    expect(entry.name).to eq('anthropic.')
    expect(entry.provider).to be_nil
  end

  context 'when a feature has no unit primitive' do
    before do
      definitions['unit_primitives'].delete_if { |up| up['feature_setting'] == 'duo_agent_platform' }
    end

    it 'flags the chat defaults and nothing else' do
      expect(entry_for('claude_haiku_4_5_20251001').is_default).to be(true)
      expect(entry_for('claude_sonnet_4_5').is_default).to be(false)
    end
  end

  it 'returns the raw value for an unknown model' do
    entry = entry_for('model_gamma_preview')

    expect(entry.to_h).to eq(
      id: 'model_gamma_preview', model_key: nil, name: 'model_gamma_preview', provider: nil, hosting: :gitlab,
      is_default: false
    )
  end

  it 'returns an empty entry for a flow with no model attribution' do
    entry = entry_for('')

    expect(entry.to_h).to eq(id: '', model_key: nil, name: nil, provider: nil, hosting: nil, is_default: false)
  end

  it 'maps the self-hosted billing placeholder to self-hosted hosting' do
    entry = entry_for('self-hosted-model')

    expect(entry.to_h).to eq(
      id: 'self-hosted-model', model_key: 'self_hosted', name: s_('DuoWorkflow|Self-hosted model'), provider: nil,
      hosting: :self_hosted, is_default: false
    )
  end

  it 'resolves a dated served id to an undated catalog ref' do
    entry = entry_for('claude-sonnet-4-6-20260301')

    expect(entry.to_h).to include(model_key: 'claude_sonnet_4_6', name: 'Claude Sonnet 4.6')
  end

  context 'when the catalog dates the direct ref but serves the model undated' do
    before do
      definitions['models'].push(
        { 'identifier' => 'claude_opus_4_6_20260205', 'name' => 'Claude Opus 4.6', 'provider' => 'Anthropic' },
        { 'identifier' => 'claude_opus_4_6_vertex', 'name' => 'Claude Opus 4.6',
          'provider' => 'Gemini Enterprise Agent Platform' }
      )
    end

    it 'resolves the undated served id across the hosting twins' do
      entry = entry_for('claude-opus-4-6')

      expect(entry.name).to eq('Claude Opus 4.6')
      expect(entry.provider).to be_nil
    end

    it 'resolves the Vertex @date form to the undated vertex ref' do
      expect(entry_for('claude-opus-4-6@20260205').provider).to eq('Gemini Enterprise Agent Platform')
    end

    it 'keys every spelling by the unhosted ref, not the shorter hosted one' do
      spellings = [
        'claude-opus-4-6', 'claude-opus-4-6@20260205', 'global.anthropic.claude-opus-4-6-v1',
        'claude_opus_4_6_vertex', 'Claude Opus 4.6 - Bedrock'
      ]

      expect(described_class.for(spellings).values.map(&:model_key).uniq).to eq(['claude_opus_4_6_20260205'])
    end
  end

  context 'with a configured self-hosted model' do
    let_it_be(:self_hosted_model) do
      create(:ai_self_hosted_model, name: 'My Mixtral', identifier: 'provider/mixtral-8x7b')
    end

    it 'matches by identifier case-insensitively and reports its configured name' do
      entry = entry_for('PROVIDER/MIXTRAL-8X7B')

      expect(entry.to_h).to eq(
        id: 'PROVIDER/MIXTRAL-8X7B', model_key: "self_hosted/#{self_hosted_model.id}", name: 'My Mixtral',
        provider: nil, hosting: :self_hosted, is_default: false
      )
    end

    it 'matches by configured name case-insensitively' do
      expect(entry_for('my mixtral').hosting).to eq(:self_hosted)
    end
  end

  context 'with several self-hosted models sharing a family and blank identifiers' do
    let_it_be(:first_configured) do
      create(:ai_self_hosted_model, name: 'Mistral Small', model: :mistral, identifier: nil)
    end

    let_it_be(:second_configured) do
      create(:ai_self_hosted_model, name: 'Mistral Large', model: :mistral, identifier: nil)
    end

    it 'resolves a bare family string to the lowest id deterministically' do
      entry = entry_for('mistral')

      expect(entry.name).to eq('Mistral Small')
      expect(entry.hosting).to eq(:self_hosted)
    end

    it 'prefers a name match over the family matches' do
      named = create(:ai_self_hosted_model, name: 'mistral', model: :codegemma, identifier: nil)

      expect(entry_for('mistral').name).to eq(named.name)
    end

    it 'prefers a non-blank identifier match over name and family matches' do
      create(:ai_self_hosted_model, name: 'mistral', model: :codegemma, identifier: nil)
      create(:ai_self_hosted_model, name: 'Routed Mistral', model: :gpt, identifier: 'MISTRAL')

      expect(entry_for('mistral').name).to eq('Routed Mistral')
    end
  end

  context 'when the model definitions fetch fails' do
    before do
      allow(::Ai::ModelSelection::ModelDefinitions).to receive(:fetch).and_return(
        ::Ai::ModelSelection::ModelDefinitions.new(ServiceResponse.error(message: 'unavailable'))
      )
    end

    it 'falls back to the raw value' do
      entry = entry_for('claude_sonnet_4_5')

      expect(entry.to_h).to eq(
        id: 'claude_sonnet_4_5', model_key: nil, name: 'claude_sonnet_4_5', provider: nil, hosting: :gitlab,
        is_default: false
      )
    end
  end

  it 'maps a batch of values in one pass' do
    result = described_class.for(['claude_sonnet_4_5', ''])

    expect(result.keys).to contain_exactly('claude_sonnet_4_5', '')
    expect(result['claude_sonnet_4_5'].name).to eq('Claude Sonnet 4.5')
    expect(result[''].name).to be_nil
  end

  describe 'model_key' do
    def model_key_for(value)
      entry_for(value).model_key
    end

    def keys_for(values)
      described_class.for(values).values.map(&:model_key)
    end

    it 'maps every spelling of a model to its bare ref' do
      spellings = [
        'claude_sonnet_4_6', 'claude_sonnet_4_6_vertex', 'claude_sonnet_4_6_20260115_vertex',
        'Claude Sonnet 4.6', 'claude-sonnet-4-6', 'claude-sonnet-4-6@20260115'
      ]

      expect(keys_for(spellings).uniq).to eq(['claude_sonnet_4_6'])
    end

    it 'maps Bedrock, Vertex and display name spellings of hosting twins to one key' do
      spellings = [
        'claude_haiku_4_5_20251001_bedrock', 'claude_haiku_4_5_20251001', 'Claude Haiku 4.5 - Bedrock',
        'us.anthropic.claude-haiku-4-5-20251001-v1:0', 'bedrock/global.anthropic.claude-haiku-4-5-20251001-v1:0',
        'eu.anthropic.claude-haiku-4-5-20251001-v1:0', 'claude-haiku-4-5@20251001'
      ]

      expect(keys_for(spellings).uniq)
        .to eq(['claude_haiku_4_5_20251001'])
    end

    it 'keys a model the catalog only hosts once by that ref' do
      expect(model_key_for('global.anthropic.claude-opus-4-6-v1')).to eq('claude_opus_4_6_bedrock')
    end

    it 'keys hosting twins without a bare ref by the shortest ref, deterministically' do
      expect(model_key_for('Twin')).to eq('twin_a')
    end

    it 'keeps routed default traffic on its own key' do
      expect(entry_for('__default__agentic_chat').to_h)
        .to include(model_key: '__default__agentic_chat', hosting: :gitlab)
    end

    it 'returns nil for unknown and empty values' do
      expect(keys_for(['model_gamma_preview', ''])).to match_array([nil, nil])
    end

    context 'with a configured self-hosted model' do
      let_it_be(:self_hosted_model) do
        create(:ai_self_hosted_model, name: 'Claude Sonnet 4.6', identifier: 'provider/sonnet')
      end

      it 'keys it by record id, apart from a catalog model with the same name' do
        expected = { model_key: "self_hosted/#{self_hosted_model.id}", hosting: :self_hosted }

        expect(entry_for('provider/sonnet').to_h).to include(expected)
        expect(entry_for('Claude Sonnet 4.6').to_h).to include(expected)
        expect(model_key_for('claude_sonnet_4_6')).to eq('claude_sonnet_4_6')
      end
    end

    context 'when the model definitions fetch fails' do
      let_it_be(:self_hosted_model) { create(:ai_self_hosted_model, name: 'My Mixtral', identifier: 'mixtral') }

      before do
        allow(::Ai::ModelSelection::ModelDefinitions).to receive(:fetch).and_return(
          ::Ai::ModelSelection::ModelDefinitions.new(ServiceResponse.error(message: 'unavailable'))
        )
      end

      it 'resolves no catalog spelling but still keys self-hosted models' do
        result = described_class.for(%w[claude_sonnet_4_6 mixtral])

        expect(result['claude_sonnet_4_6'].model_key).to be_nil
        expect(result['mixtral'].model_key).to eq("self_hosted/#{self_hosted_model.id}")
      end

      it 'reports the catalog as unavailable' do
        expect(described_class.new([]).catalog_available?).to be(false)
      end
    end

    it 'reports the catalog as available when the fetch succeeds' do
      expect(described_class.new([]).catalog_available?).to be(true)
    end
  end

  describe 'alias keys as grouped values' do
    it 'gives a twin set key no single provider' do
      expect(entry_for('claude_sonnet_4_6').to_h).to include(name: 'Claude Sonnet 4.6', provider: nil)
    end

    it 'keeps the provider of a hosted twin ref' do
      expect(entry_for('claude_sonnet_4_6_vertex').provider).to eq('Gemini Enterprise Agent Platform')
    end

    it 'flags a twin set key as default when another twin is the default' do
      definitions['unit_primitives'][1]['default_model'] = 'claude_sonnet_4_6_vertex'

      expect(entry_for('claude_sonnet_4_6').is_default).to be(true)
    end

    it 'resolves the self-hosted key' do
      expect(entry_for('self_hosted').to_h).to eq(
        id: 'self_hosted', model_key: 'self_hosted', name: s_('DuoWorkflow|Self-hosted model'), provider: nil,
        hosting: :self_hosted, is_default: false
      )
    end

    it 'keeps the grouped value as id so a model pairs across periods' do
      spellings = ['claude_sonnet_4_6', 'claude-sonnet-4-6@20260115', 'model_gamma_preview']

      expect(described_class.for(spellings).transform_values(&:id)).to eq(spellings.index_with(&:itself))
    end

    context 'with a configured self-hosted model' do
      let_it_be(:self_hosted_model) { create(:ai_self_hosted_model, name: 'My Mixtral') }

      it 'resolves its record key to the configured name' do
        expect(entry_for("self_hosted/#{self_hosted_model.id}").to_h).to include(
          name: 'My Mixtral', hosting: :self_hosted
        )
      end

      it 'keeps a catalog key when a configured model is spelled like it' do
        create(:ai_self_hosted_model, name: 'claude_sonnet_4_6')
        create(:ai_self_hosted_model, name: 'Sonnet Proxy', identifier: 'claude_sonnet_4_6')

        expect(entry_for('claude_sonnet_4_6').to_h).to include(
          model_key: 'claude_sonnet_4_6', name: 'Claude Sonnet 4.6', hosting: :gitlab
        )
      end

      it 'keeps the self-hosted key when a configured model is named like it' do
        create(:ai_self_hosted_model, name: 'self_hosted')

        expect(entry_for('self_hosted').to_h).to include(
          model_key: 'self_hosted', name: s_('DuoWorkflow|Self-hosted model')
        )
      end

      it 'keeps a record key for a deleted record self-hosted' do
        expect(entry_for("self_hosted/#{non_existing_record_id}").to_h).to include(
          name: s_('DuoWorkflow|Self-hosted model'), hosting: :self_hosted
        )
      end
    end
  end
end
