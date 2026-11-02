# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ai::Catalog::Skills::BlobCheck, feature_category: :ai_catalog_curation do
  using RSpec::Parameterized::TableSyntax

  describe '.rejection_for' do
    subject(:rejection) { described_class.rejection_for(blob) }

    let(:path) { 'skills/cosign/SKILL.md' }
    let(:readable) { { stored_externally?: false, truncated?: false, binary?: false, data: "---\nname: x\n---\n" } }

    # Not a verifying double: Blob defines stored_externally? itself but delegates path, data,
    # binary? and truncated? to Gitlab::Git::Blob, so neither class verifies the whole surface.
    let(:blob) { double(path: path, **readable, **overrides) } # rubocop:disable RSpec/VerifiedDoubles -- see above

    context 'when the blob is readable text' do
      let(:overrides) { {} }

      it { is_expected.to be_nil }
    end

    context 'when the blob cannot be read as a skill' do
      where(:case_name, :overrides, :code, :message) do
        'stored in Git LFS' | { stored_externally?: true } | :stored_in_lfs |
          'The file is stored in Git LFS, which the AI Catalog cannot read.'
        'truncated by the read limit' | { truncated?: true } | :file_too_large |
          'The file is too large to read.'
        'binary' | { binary?: true } | :not_utf8_text | 'The file is not UTF-8 text.'
        'without data' | { data: nil } | :not_utf8_text | 'The file is not UTF-8 text.'
        'not valid UTF-8' | { data: "---\n\xC3\x28" } | :not_utf8_text |
          'The file is not UTF-8 text.'
      end

      with_them do
        it 'returns a platform rejection for the path' do
          expect(rejection).to eq(
            Gitlab::Ai::Catalog::Skills::Validator::Rejection.new(
              path: path, code: code, message: message, category: :platform
            )
          )
        end
      end
    end
  end
end
