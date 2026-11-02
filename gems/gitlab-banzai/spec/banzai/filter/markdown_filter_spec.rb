# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Banzai::Filter::MarkdownFilter do
  using RSpec::Parameterized::TableSyntax

  let(:engine) do
    Class.new(Banzai::Filter::MarkdownEngines::Base) do
      def render(text)
        "<p>#{CGI.escapeHTML(text)}</p>\n"
      end
    end
  end

  before do
    stub_const('Banzai::Filter::MarkdownEngines::Stand', engine)
  end

  describe 'markdown engine from context' do
    it 'finds the engine named in the context' do
      expect(described_class.new('foo', { markdown_engine: :stand }).render_engine).to eq(engine)
    end

    it 'raises for an unknown engine' do
      expect { described_class.new('foo', { markdown_engine: :foo_bar }) }.to raise_error(NameError)
    end
  end

  describe '#call' do
    it 'renders through the engine, without carriage returns or trailing whitespace' do
      expect(described_class.new("foo\r\nbar", { markdown_engine: :stand }).call).to eq("<p>foo\nbar</p>")
    end
  end

  describe '.parse_sourcepos' do
    where(:sourcepos, :expected) do
      '1:1-1:4'     | { start: { line: 0, column: 0 }, end: { line: 0, column: 3 } }
      '12:22-1:456' | { start: { line: 11, column: 21 }, end: { line: 0, column: 455 } }
      '0:0-0:0'     | { start: { line: 0, column: 0 }, end: { line: 0, column: 0 } }
      nil           | nil
      '1-2:3'       | nil
      '1:2'         | nil
      '1:2-3'       | nil
      '-1:2-3:-4'   | nil
    end

    with_them do
      it 'parses' do
        expect(described_class.parse_sourcepos(sourcepos)).to eq expected
      end
    end
  end
end
