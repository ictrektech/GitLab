# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Ai::Catalog::Skills::Path, feature_category: :ai_catalog_curation do
  using RSpec::Parameterized::TableSyntax

  describe 'REGEX' do
    where(:path, :matches) do
      'skills/cosign/SKILL.md'      | true
      'skills/co-sign/SKILL.md'     | true
      'skills/cosign/SKILL.mdx'     | false
      'skills/cosign/skill.md'      | false
      'skills/cosign/README.md'     | false
      'skills/SKILL.md'             | false
      'skills/a/b/SKILL.md'         | false
      'docs/SKILL.md'               | false
      'SKILL.md'                    | false
      'my-skills/cosign/SKILL.md'   | false
      # Anchored to the whole string: a git path may contain a newline, and Ruby's ^ and $ would
      # match a skill path on any line of one.
      "x\nskills/cosign/SKILL.md"   | false
      "skills/cosign/SKILL.md\nx"   | false
    end

    with_them do
      it { expect(described_class::REGEX.match?(path)).to be(matches) }
    end

    it 'matches a path built from the same fragments the scaffolder writes' do
      path = File.join(described_class::ROOT, 'cosign', described_class::FILENAME)

      expect(described_class::REGEX.match?(path)).to be(true)
    end
  end
end
