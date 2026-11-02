# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ai::Catalog::Skills::Validator, feature_category: :ai_catalog_curation do
  using RSpec::Parameterized::TableSyntax

  describe '.execute' do
    subject(:result) { described_class.execute(path: path, content: content) }

    let(:path) { 'skills/cosign/SKILL.md' }

    def skill(front_matter)
      "---\n#{front_matter}---\n\nBody\n"
    end

    def rejections
      result.rejections.map { |rejection| [rejection.code, rejection.category, rejection.message] }
    end

    context 'with a conformant skill' do
      let(:content) { skill("name: cosign\ndescription: Signs blobs\n") }

      it 'is valid and returns the specification fields', :aggregate_failures do
        expect(result).to be_valid
        expect(result.path).to eq(path)
        expect(result.attributes).to eq('name' => 'cosign', 'description' => 'Signs blobs', 'metadata' => {})
      end
    end

    context 'with every optional specification field' do
      let(:content) do
        skill(<<~YAML)
          name: cosign
          description: Signs blobs
          license: Apache-2.0
          compatibility: Requires cosign and network access
          allowed-tools: Bash(cosign:*) Read
          metadata:
            visibility: public
          model: sonnet
        YAML
      end

      it 'returns them, with allowed-tools as allowed_tools and unknown keys dropped', :aggregate_failures do
        expect(result).to be_valid
        expect(result.attributes).to eq(
          'name' => 'cosign',
          'description' => 'Signs blobs',
          'license' => 'Apache-2.0',
          'compatibility' => 'Requires cosign and network access',
          'allowed_tools' => 'Bash(cosign:*) Read',
          'metadata' => { 'visibility' => 'public' }
        )
      end
    end

    context 'with dates in the front matter' do
      let(:content) { skill("name: cosign\ndescription: Signs blobs\nreleased: 2026-01-01\n") }

      it { is_expected.to be_valid }
    end

    context 'with a single-character name, which the specification allows' do
      let(:path) { 'skills/x/SKILL.md' }
      let(:content) { skill("name: x\ndescription: Signs blobs\n") }

      it { is_expected.to be_valid }
    end

    context 'when the file is rejected' do
      where(:case_name, :content, :code, :category, :message) do
        'no front matter' | "# Just a heading\n" | :no_frontmatter | :spec |
          'SKILL.md must start with YAML front matter between --- lines.'
        'TOML front matter' | "+++\nname = \"cosign\"\n+++\n" | :no_frontmatter | :spec |
          'SKILL.md must start with YAML front matter between --- lines.'
        'YAML that does not parse' | "---\nname: [unclosed\n---\n" | :invalid_yaml | :spec |
          'The YAML front matter could not be parsed.'
        'YAML with a disallowed class' | "---\nname: :cosign\ndescription: d\n---\n" | :invalid_yaml | :spec |
          'The YAML front matter could not be parsed.'
        'YAML with a malformed tag' | "---\nname: !!float x\ndescription: d\n---\n" | :invalid_yaml | :spec |
          'The YAML front matter could not be parsed.'
        'front matter that is a list' | "---\n- cosign\n---\n" | :frontmatter_not_a_mapping | :spec |
          'The YAML front matter must be a mapping of fields.'
        'missing name' | "---\ndescription: d\n---\n" | :invalid_name | :spec |
          'name is required.'
        'name that is not text' | "---\nname: 3\ndescription: d\n---\n" | :invalid_name | :spec |
          'name must be text.'
        'missing description' | "---\nname: cosign\n---\n" | :invalid_description | :spec |
          'description is required.'
        'blank description' | "---\nname: cosign\ndescription:\n---\n" | :invalid_description | :spec |
          'description must not be empty.'
        'empty description' | "---\nname: cosign\ndescription: ''\n---\n" | :invalid_description | :spec |
          'description must not be empty.'
        'description over 1024 characters' | "---\nname: cosign\ndescription: #{'a' * 1025}\n---\n" |
          :invalid_description | :spec | 'description must be 1024 characters or fewer.'
        'compatibility over 500 characters' | "---\nname: cosign\ndescription: d\ncompatibility: #{'a' * 501}\n---\n" |
          :invalid_compatibility | :spec | 'compatibility must be 500 characters or fewer.'
        'metadata that is not a mapping' | "---\nname: cosign\ndescription: d\nmetadata: public\n---\n" |
          :invalid_metadata | :spec | 'metadata must be a mapping.'
        'a metadata value that is not text' | "---\nname: cosign\ndescription: d\nmetadata:\n  retries: 3\n---\n" |
          :invalid_metadata | :spec | 'metadata.retries must be text.'
        'a metadata key that needs escaping' | "---\nname: cosign\ndescription: d\nmetadata:\n  a/b~c: 3\n---\n" |
          :invalid_metadata | :spec | 'metadata.a/b~c must be text.'
        'allowed-tools that is not text' | "---\nname: cosign\ndescription: d\nallowed-tools: [Read]\n---\n" |
          :invalid_allowed_tools | :spec | 'allowed-tools must be text.'
        'license over the GitLab limit' | "---\nname: cosign\ndescription: d\nlicense: #{'a' * 256}\n---\n" |
          :invalid_license | :platform | 'license must be 255 characters or fewer.'
        'allowed-tools over the GitLab limit' |
          "---\nname: cosign\ndescription: d\nallowed-tools: #{'a' * 1025}\n---\n" |
          :invalid_allowed_tools | :platform | 'allowed-tools must be 1024 characters or fewer.'
        'name that does not match its directory' | "---\nname: sigstore\ndescription: d\n---\n" |
          :name_directory_mismatch | :spec | 'name must match the parent directory name, cosign.'
      end

      with_them do
        it 'reports the rejection against the path', :aggregate_failures do
          expect(result).not_to be_valid
          expect(result.attributes).to be_nil
          expect(rejections).to contain_exactly([code, category, message])
          expect(result.rejections.map(&:path)).to all(eq(path))
        end
      end
    end

    context 'when the name breaks the naming rules' do
      let(:content) { skill("name: #{name}\ndescription: d\n") }
      let(:path) { "skills/#{name}/SKILL.md" }
      let(:pattern_message) do
        'name must contain only lowercase letters, numbers, and hyphens. ' \
          'It cannot start or end with a hyphen, or contain two hyphens in a row.'
      end

      where(:name) { %w[Cosign co--sign -cosign cosign-] }

      with_them do
        it 'explains the rule' do
          expect(rejections).to contain_exactly([:invalid_name, :spec, pattern_message])
        end
      end
    end

    context 'when the name is longer than the specification allows' do
      let(:name) { 'a' * 65 }
      let(:path) { "skills/#{name}/SKILL.md" }
      let(:content) { skill("name: #{name}\ndescription: d\n") }

      it 'reports the limit read from the schema' do
        expect(rejections).to contain_exactly([:invalid_name, :spec, 'name must be 64 characters or fewer.'])
      end
    end

    context 'when the front matter is empty' do
      let(:content) { skill('') }

      it 'reports each missing field rather than the shape of the front matter' do
        expect(rejections).to contain_exactly(
          [:invalid_name, :spec, 'name is required.'],
          [:invalid_description, :spec, 'description is required.']
        )
      end
    end

    context 'when the name spans lines' do
      let(:content) { skill("name: \"cosign\\nx\"\ndescription: d\n") }

      it 'applies the pattern to the whole value' do
        expect(result.rejections.map(&:code)).to contain_exactly(:invalid_name, :name_directory_mismatch)
      end
    end

    context 'when there are several problems' do
      let(:content) { skill("name: Bad\ndescription: ''\nlicense: #{'a' * 256}\n") }

      it 'reports all of them rather than stopping at the first' do
        expect(result.rejections.map(&:code))
          .to contain_exactly(:invalid_name, :invalid_description, :invalid_license, :name_directory_mismatch)
      end
    end

    describe 'front matter size' do
      let(:base) { "name: cosign\ndescription: d\n# " }
      let(:content) { skill("#{base}#{'a' * (bytes - base.bytesize - 1)}\n") }

      context 'when it is at the limit' do
        let(:bytes) { 16.kilobytes }

        it { is_expected.to be_valid }
      end

      context 'when it is over the limit' do
        let(:bytes) { 16.kilobytes + 1 }

        # The unit label comes from the Rails locale (KiB in GitLab), so build it the same way.
        let(:message) do
          size = ActiveSupport::NumberHelper.number_to_human_size(16.kilobytes)

          "The YAML front matter must be #{size} or smaller."
        end

        it 'rejects it before parsing' do
          expect(YAML).not_to receive(:safe_load)

          expect(rejections).to contain_exactly([:frontmatter_too_large, :platform, message])
        end
      end
    end

    describe 'front matter nesting' do
      # The root mapping is one level, so `levels` of brackets nest levels + 1 deep.
      def nested(levels)
        skill("name: cosign\ndescription: d\nnested: #{'[' * levels}#{']' * levels}\n")
      end

      let(:too_deep) { [:frontmatter_too_deep, :platform, 'The YAML front matter is nested too deeply.'] }

      context 'when it is at the limit' do
        let(:content) { nested(19) }

        it { is_expected.to be_valid }
      end

      context 'when it is over the limit' do
        let(:content) { nested(20) }

        it { expect(rejections).to contain_exactly(too_deep) }
      end

      # Psych builds objects recursively, and Puma and Sidekiq threads have smaller stacks than
      # the main thread: this overflowed the stack well inside the size limit.
      context 'when it is deep enough to overflow a thread stack' do
        let(:content) { nested(8_000) }

        it 'rejects it without raising' do
          expect(content.bytesize).to be < 16.kilobytes

          result = Thread.new { described_class.execute(path: path, content: content) }.value

          expect(result.rejections.map(&:code)).to contain_exactly(:frontmatter_too_deep)
        end
      end

      context 'when it is too deep and has a syntax error' do
        let(:content) { skill("nested: #{'[' * 30}\n") }

        it 'reports whichever the parser reaches first' do
          expect(rejections).to contain_exactly(too_deep)
        end
      end

      context 'when the syntax error comes before the nesting limit' do
        let(:content) { skill("name: 'unclosed\nnested: #{'[' * 30}\n") }

        it 'reports invalid YAML' do
          expect(result.rejections.map(&:code)).to contain_exactly(:invalid_yaml)
        end
      end
    end

    context 'when a rule applies to the front matter as a whole' do
      let(:content) { skill("name: cosign\ndescription: d\n") }

      before do
        allow(described_class).to receive(:schema)
          .and_return(JSONSchemer.schema({ 'type' => 'object', 'maxProperties' => 1 }))
      end

      it 'falls back to a front matter code' do
        expect(rejections).to contain_exactly([:invalid_frontmatter, :spec, 'The YAML front matter is not valid.'])
      end
    end

    context 'when a schema limit changes' do
      let(:content) { skill("name: cosign\ndescription: ab\n") }

      before do
        allow(described_class).to receive(:schema).and_return(
          JSONSchemer.schema({ 'properties' => { 'description' => { 'type' => 'string', 'minLength' => 3 } } })
        )
      end

      it 'reports the new limit without a code change' do
        expect(rejections)
          .to contain_exactly([:invalid_description, :spec, 'description must be at least 3 characters.'])
      end
    end

    context 'when the schema gains a rule with no specific message' do
      let(:content) { skill("name: cosign\ndescription: d\n") }

      before do
        allow(described_class).to receive(:schema)
          .and_return(JSONSchemer.schema({ 'properties' => { 'description' => rule } }))
      end

      where(:case_name, :rule) do
        'a pattern on a field other than name' | { 'pattern' => '^[A-Z]' }
        'a rule type with no message of its own' | { 'enum' => %w[Signs] }
      end

      with_them do
        it 'says the field is not valid' do
          expect(rejections).to contain_exactly([:invalid_description, :spec, 'description is not valid.'])
        end
      end
    end
  end
end
