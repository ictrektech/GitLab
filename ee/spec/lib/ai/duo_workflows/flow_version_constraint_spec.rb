# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Ai::DuoWorkflows::FlowVersionConstraint, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  describe '.satisfied_by?' do
    where(:version, :constraint, :satisfied) do
      '1.0.0'             | '1.0.0'             | true
      '1.2.0'             | '1.0.0'             | false
      '2.1.0-interactive' | '2.1.0-interactive' | true
      '4.0.0'             | '^4.0.0'            | true
      '4.1.3'             | '^4.0.0'            | true
      '4.2.0'             | '^4.3.0'            | false
      '5.0.0'             | '^4.0.0'            | false
      '3.9.0'             | '^4.0.0'            | false
      '4.1.0-dev'         | '^4.0.0'            | false
      '4.1'               | '^4.0.0'            | false
      '0.2.0'             | '^0.1.0'            | false
      '1.0.4'             | '~1.0'              | false
      '1.0.4'             | '>=1.0.0'           | false
      nil                 | '^4.0.0'            | false
      4                   | '^4.0.0'            | false
      ['4.0.0']           | '^4.0.0'            | false
      '4.0.0'             | nil                 | false
      ''                  | ''                  | false
    end

    with_them do
      it { expect(described_class.satisfied_by?(version, constraint)).to be(satisfied) }
    end
  end
end
