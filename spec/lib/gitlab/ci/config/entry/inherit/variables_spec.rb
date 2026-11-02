# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ::Gitlab::Ci::Config::Entry::Inherit::Variables, feature_category: :pipeline_composition do
  using RSpec::Parameterized::TableSyntax

  subject { described_class.new(config) }

  context 'validations' do
    where(:config, :valid) do
      true        | true
      false       | true
      %w[A]       | true
      %w[A B]     | true
      %i[image]   | true
      [true]      | false
      "string"    | false
    end

    with_them do
      it 'reports whether the config is valid' do
        expect(subject.valid?).to eq(valid)
      end
    end
  end
end
