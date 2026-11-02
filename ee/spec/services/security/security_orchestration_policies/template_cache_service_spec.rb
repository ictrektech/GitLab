# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecurityOrchestrationPolicies::TemplateCacheService, "#fetch", feature_category: :security_policy_management do
  let(:scan_type) { "sast" }
  let(:scan_template) { 'default' }

  subject(:fetch) { described_class.new.fetch(scan_type, template: scan_template) }

  Security::SecurityOrchestrationPolicies::CiAction::Template::SCAN_TEMPLATES.each_key do |scan_type|
    context scan_type.to_s do
      it { is_expected.to be_a(Hash).and satisfy(&:any?) }

      context "when fetching latest template" do
        let(:scan_template) { 'latest' }

        it { is_expected.to be_a(Hash).and satisfy(&:any?) }
      end

      if Security::SecurityOrchestrationPolicies::CiAction::Template::SCAN_TYPES_WITH_VERSIONED_TEMPLATES
        .key?(scan_type.to_sym)
        context "when fetching versioned template" do
          let(:scan_template) { 'v1' }

          it { is_expected.to be_a(Hash).and satisfy(&:any?) }
        end
      end
    end
  end

  describe "cache misses" do
    it "instantiates" do
      expect(::TemplateFinder).to receive(:build).with(:gitlab_ci_ymls, nil, name: "Jobs/SAST").and_call_original

      fetch
    end

    context "when cache matches `scan_type` but not `latest`" do
      before do
        described_class.new.fetch(scan_type, template: "default")
      end

      it "instantiates" do
        expect(::TemplateFinder).to receive(:build).and_call_original

        fetch
      end
    end

    context "when fetching latest template" do
      let(:scan_template) { 'latest' }

      it "instantiates" do
        expect(::TemplateFinder).to receive(:build).with(:gitlab_ci_ymls, nil,
          name: "Jobs/SAST.latest").and_call_original

        fetch
      end
    end

    context "when fetching versioned template for versioned scan type" do
      let(:scan_type) { "dependency_scanning" }
      let(:scan_template) { "v2" }

      it "instantiates" do
        expect(::TemplateFinder).to receive(:build).with(:gitlab_ci_ymls, nil,
          name: "Jobs/Dependency-Scanning.v2").and_call_original

        fetch
      end
    end
  end

  describe "inputs forwarding" do
    let(:template_with_inputs) do
      <<~YAML
        ---
        spec:
          inputs:
            analyzer_image:
              default: default-image
        ---
        my-job:
          script: ['echo']
          variables:
            ANALYZER_IMAGE: $[[ inputs.analyzer_image ]]
      YAML
    end

    before do
      finder = instance_double(::TemplateFinder, execute: instance_double(
        ::Gitlab::Template::GitlabCiYmlTemplate, content: template_with_inputs
      ))
      allow(::TemplateFinder).to receive(:build).and_return(finder)
    end

    it "substitutes a provided input value into the resulting configuration" do
      result = described_class.new.fetch(
        scan_type, template: scan_template, inputs: { analyzer_image: 'custom-image' }
      )

      expect(result.dig(:"my-job", :variables, :ANALYZER_IMAGE)).to eq('custom-image')
    end

    it "falls back to the input's default when inputs is empty" do
      result = described_class.new.fetch(scan_type, template: scan_template, inputs: {})

      expect(result.dig(:"my-job", :variables, :ANALYZER_IMAGE)).to eq('default-image')
    end

    it "keys the cache by inputs, returning distinct results for distinct inputs on the same instance" do
      service = described_class.new

      first = service.fetch(scan_type, template: scan_template, inputs: { analyzer_image: 'first-image' })
      second = service.fetch(scan_type, template: scan_template, inputs: { analyzer_image: 'second-image' })

      expect(first.dig(:"my-job", :variables, :ANALYZER_IMAGE)).to eq('first-image')
      expect(second.dig(:"my-job", :variables, :ANALYZER_IMAGE)).to eq('second-image')
    end

    it "accepts string keys and shares the cache entry with the same symbol keys", :aggregate_failures do
      service = described_class.new

      expect(Gitlab::Ci::Config).to receive(:new).once.and_call_original

      string_keyed = service.fetch(scan_type, template: scan_template, inputs: { 'analyzer_image' => 'custom-image' })
      symbol_keyed = service.fetch(scan_type, template: scan_template, inputs: { analyzer_image: 'custom-image' })

      expect(string_keyed.dig(:"my-job", :variables, :ANALYZER_IMAGE)).to eq('custom-image')
      expect(symbol_keyed).to eq(string_keyed)
    end

    it "hits the cache for equal inputs and ignores later mutation of the caller's hash", :aggregate_failures do
      service = described_class.new
      inputs = { analyzer_image: 'custom-image' }

      expect(Gitlab::Ci::Config).to receive(:new).once.and_call_original

      service.fetch(scan_type, template: scan_template, inputs: inputs)
      inputs[:analyzer_image] = 'mutated-image'
      service.fetch(scan_type, template: scan_template, inputs: { analyzer_image: 'custom-image' })
      result = service.fetch(scan_type, template: scan_template, inputs: { analyzer_image: 'custom-image' })

      expect(result.dig(:"my-job", :variables, :ANALYZER_IMAGE)).to eq('custom-image')
    end
  end

  describe "cache hits" do
    before do
      fetch
    end

    it "does not instantiate" do
      expect(::TemplateFinder).not_to receive(:build)

      fetch
    end

    context "when cache key includes version" do
      let(:scan_type) { "sast" }
      let(:scan_template) { "v1" }

      before do
        described_class.new.fetch(scan_type, template: scan_template)
      end

      it "does not instantiate" do
        expect(::TemplateFinder).not_to receive(:build)

        fetch
      end
    end
  end
end
