# frozen_string_literal: true

require 'fast_spec_helper'
require 'shellwords'
require 'yaml'
require_relative '../../../scripts/ci/otel_span_exporter'

RSpec.describe 'CI otel_span call sites', feature_category: :tooling do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:options) { %w[--kind --operation --attempt --rspec-report --rspec-report-count] }

  it 'uses explicit command separators and supported options at every literal call site', :aggregate_failures do
    files = Dir.glob("#{root}/.gitlab/ci/**/*.{yml,yaml,erb}") + Dir.glob("#{root}/scripts/*.sh")
    calls = files.flat_map do |path|
      content = File.read(path)
      content = YAML.parse_stream(content).grep(Psych::Nodes::Scalar).map(&:value).join("\n") unless path.end_with?(
        '.sh', '.erb')

      content.gsub(/\\\n\s*/, ' ').lines.filter_map do |line|
        next if line.lstrip.start_with?('#')
        next unless line.match?(/(?:^|\s)otel_span\s+(?:--|[a-z])/)
        next if line.include?('Usage: otel_span')

        [path.delete_prefix("#{root}/"), line.split(/\botel_span\s+/, 2).last]
      end
    end

    expect(calls).not_to be_empty
    calls.each do |path, call|
      tokens = Shellwords.split(call)
      while options.include?(tokens.first)
        option = tokens.shift
        value = tokens.shift
        expect(value).not_to be_nil, "#{path}: missing value for #{option}"
        expect(value).not_to eq('--'), "#{path}: missing value for #{option}"

        if option == '--kind'
          expect(OtelSpanExporter::OPERATION_KINDS).to include(value), "#{path}: unsupported operation kind #{value}"
        end
      end

      tokens.shift unless tokens.first == '--'
      expect(tokens.shift).to eq('--'), "#{path}: invalid otel_span call: #{call}"
      expect(tokens.first).not_to be_nil, "#{path}: missing command"
    end
  end
end
