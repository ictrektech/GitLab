# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::WorkItems::DuoQuestion, feature_category: :team_planning do
  def fenced(payload)
    "@root Which provider should we use?\n\n```json:duo-question\n#{payload.to_json}\n```\n"
  end

  describe '.payload_hint?' do
    using RSpec::Parameterized::TableSyntax

    where(:body, :expected) do
      "```json:duo-question\n{}\n```"       | true
      '<!-- duo:options ["Okta"] -->'       | true
      'An ordinary comment'                 | false
      nil                                   | false
    end

    with_them do
      it { expect(described_class.payload_hint?(body)).to be(expected) }
    end
  end

  describe '.parse' do
    it 'returns nil for a body without a payload' do
      expect(described_class.parse('An ordinary comment')).to be_nil
    end

    it 'parses a fenced payload, including the question' do
      body = fenced(
        type: 'closed',
        question: '  Which   provider should we use? ',
        multiple: true,
        options: [
          { id: 'okta', label: 'Okta', description: 'Hosted.', recommended: true },
          { id: 'entra', label: 'Entra ID', description: '   ' },
          { id: 'broken' },
          'Not an object'
        ]
      )

      expect(described_class.parse(body)).to eq(
        type: 'closed',
        question: 'Which provider should we use?',
        multiple: true,
        declared_count: 4,
        options: [
          { label: 'Okta', description: 'Hosted.', recommended: true },
          { label: 'Entra ID', description: nil, recommended: false }
        ]
      )
    end

    it 'leaves the question empty when the fenced payload has none' do
      expect(described_class.parse(fenced(type: 'open'))).to include(type: 'open', question: nil, options: [])
    end

    it 'returns nil when the fenced payload is not a JSON object' do
      expect(described_class.parse("```json:duo-question\n[1, 2]\n```\n")).to be_nil
    end

    it 'parses a marker payload, which carries no question' do
      body = "Which provider?\n\n<!-- duo:options [\"Okta\", \"Entra ID\"] duo:recommended 2 duo:multiple -->\n"

      expect(described_class.parse(body)).to eq(
        type: 'closed',
        question: nil,
        multiple: true,
        declared_count: 2,
        options: [
          { label: 'Okta', description: nil, recommended: false },
          { label: 'Entra ID', description: nil, recommended: true }
        ]
      )
    end

    it 'returns nil when the marker carries no label array' do
      expect(described_class.parse("Which provider?\n\n<!-- duo:options duo:recommended 1 -->\n")).to be_nil
    end

    it 'returns nil when a payload hint only appears inline in prose' do
      expect(described_class.parse('We mention `duo:options` and `json:duo-question` inline.')).to be_nil
    end

    it 'prefers the fenced payload when a body carries both' do
      body = "#{fenced(type: 'closed', question: 'Fenced?', options: [{ id: 'a', label: 'A' }])}" \
        "<!-- duo:options [\"B\"] -->\n"

      expect(described_class.parse(body)).to include(question: 'Fenced?', options: [include(label: 'A')])
    end
  end

  describe '.strip_payloads' do
    it 'removes every payload and keeps the prose' do
      body = "#{fenced(type: 'open')}<!-- duo:options [\"Okta\"] -->\nTrailing prose."

      expect(described_class.strip_payloads(body)).to eq("@root Which provider should we use?\n\nTrailing prose.")
    end
  end
end
