# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Ci::Config::Interpolation::Functions::Truncate, feature_category: :pipeline_composition do
  it 'matches exactly the truncate function with 2 numeric arguments' do
    expect(described_class.matches?('truncate(1,2)')).to be_truthy
    expect(described_class.matches?('truncate( 11 , 222 )')).to be_truthy
    expect(described_class.matches?('truncate( string , 222 )')).to be_falsey
    expect(described_class.matches?('truncate(222)')).to be_falsey
    expect(described_class.matches?('unknown(1,2)')).to be_falsey
  end

  it 'truncates the given input' do
    function = described_class.new('truncate(1,2)', nil)

    output = function.execute('test')

    expect(function).to be_valid
    expect(output).to eq('es')
  end

  context 'when an argument reaches past the end of the input' do
    using RSpec::Parameterized::TableSyntax

    where(:function_expression, :expected_output) do
      'truncate(0,4)'                                         | 'test'
      'truncate(1,9223372036854775807)'                       | 'est'
      'truncate(1,9223372036854775808)'                       | 'est'
      'truncate(0,99999999999999999999)'                      | 'test'
      'truncate(4,1)'                                         | ''
      'truncate(5,1)'                                         | ''
      'truncate(99999999999999999999,2)'                      | ''
      'truncate(99999999999999999999,99999999999999999999)'   | ''
    end

    with_them do
      it 'returns the part of the input that exists', :aggregate_failures do
        function = described_class.new(function_expression, nil)

        output = function.execute('test')

        expect(function).to be_valid
        expect(output).to eq(expected_output)
      end
    end
  end

  context 'when given a non-string input' do
    it 'returns an error' do
      function = described_class.new('truncate(1,2)', nil)

      function.execute(100)

      expect(function).not_to be_valid
      expect(function.errors).to contain_exactly(
        'error in `truncate` function: invalid input type: truncate can only be used with string inputs'
      )
    end
  end
end
