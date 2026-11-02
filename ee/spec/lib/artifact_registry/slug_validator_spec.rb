# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::SlugValidator, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject(:validator) { described_class.new(slug) }

  let(:length_message) do
    format(s_('ArtifactRegistry|Must be between %{min} and %{max} characters.'), min: 3, max: 63)
  end

  let(:charset_message) do
    s_('ArtifactRegistry|Only lowercase letters, digits and hyphens (-) are allowed. ' \
      'Remove any spaces or special characters.')
  end

  let(:boundary_message) { s_('ArtifactRegistry|Must start and end with an alphanumeric character.') }
  let(:consecutive_message) { s_('ArtifactRegistry|Must not contain consecutive hyphens (--).') }

  describe '#result' do
    context 'with a slug that satisfies every rule' do
      where(:slug) do
        [
          'abc',              # minimum length
          'a' * 63,           # maximum length
          'valid-slug-1'
        ]
      end

      with_them do
        it 'succeeds' do
          expect(validator.result).to be_success
          expect(validator).to be_valid
        end
      end
    end

    context 'with a slug that breaks exactly one rule' do
      # Each slug fails only the named rule, so each rule has independent coverage.
      where(:rule, :slug, :message) do
        'too short'              | 'ab'        | ref(:length_message)
        'too long'               | ('a' * 64)  | ref(:length_message)
        'disallowed character'   | 'bad.slug'  | ref(:charset_message)
        'uppercase letter'       | 'aBc'       | ref(:charset_message)
        'leading hyphen'         | '-slug'     | ref(:boundary_message)
        'trailing hyphen'        | 'slug-'     | ref(:boundary_message)
        'hyphens at both ends'   | '-slug-'    | ref(:boundary_message)
        'consecutive hyphens'    | 'a--b'      | ref(:consecutive_message)
      end

      with_them do
        it "is refused with the invalid_slug reason and that rule's message", :aggregate_failures do
          expect(validator).not_to be_valid
          expect(validator.result).to be_error
          expect(validator.result.reason).to eq(:invalid_slug)
          expect(validator.result.message).to eq(message)
        end
      end
    end

    context 'with a blank slug' do
      where(:slug) { ['', nil] }

      with_them do
        it 'is refused for its length, its characters and its boundary' do
          expect(validator.result.message).to eq([length_message, charset_message, boundary_message].join(' '))
        end
      end
    end

    context 'when a slug breaks every rule at once' do
      let(:slug) { "-A--#{'a' * 60}" } # too long, uppercase, leading hyphen, consecutive hyphens

      it 'joins every violated rule into one message in rule order' do
        expect(validator.result.message)
          .to eq([length_message, charset_message, boundary_message, consecutive_message].join(' '))
      end

      # The default test locale is English, so only a translated locale catches a rule that skips s_().
      context 'when the locale translates the rules' do
        around do |example|
          Gitlab::I18n.with_locale(:fr) { example.run }
        end

        it 'returns every rule in that locale' do
          expect(validator.result.message)
            .to eq([length_message, charset_message, boundary_message, consecutive_message].join(' '))
        end
      end
    end
  end
end
