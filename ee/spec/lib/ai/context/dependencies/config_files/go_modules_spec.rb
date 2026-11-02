# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Context::Dependencies::ConfigFiles::GoModules, feature_category: :code_suggestions do
  it 'returns the expected language value' do
    expect(described_class.lang).to eq('go')
  end

  it_behaves_like 'parsing a valid dependency config file' do
    let(:config_file_content) do
      <<~CONTENT
        module github.com/my-mod/my-mod

        go 1.22

        require golang.org/x/mod v0.15.0
        require github.com/pmezard/go-difflib v1.0.0 // indirect

        require (
          github.com/kr/text v0.2.0 // indirect
          go.uber.org/goleak v1.3.0
        )

        require (
          github.com/go-http-utils/headers v0.0.0-20181008091004-fed159eddc2a
        )

        exclude (
          example.com/other-module v1.3.0
        )
      CONTENT
    end

    let(:expected_formatted_lib_names) do
      [
        'golang.org/x/mod (0.15.0)',
        'go.uber.org/goleak (1.3.0)',
        'github.com/go-http-utils/headers (0.0.0)'
      ]
    end
  end

  it_behaves_like 'stopping at the library cap' do
    let(:config_file_content) do
      <<~CONTENT
        require (
          example.com/lib1 v1.0.0
          example.com/lib2 v2.0.0
          example.com/lib3 v3.0.0
        )
      CONTENT
    end

    let(:expected_formatted_lib_names) { ['example.com/lib1 (1.0.0)', 'example.com/lib2 (2.0.0)'] }
  end

  context 'when the file has no require directive' do
    it_behaves_like 'parsing an invalid dependency config file' do
      let(:invalid_config_file_content) do
        <<~CONTENT
          module github.com/my-mod/my-mod

          go 1.22
        CONTENT
      end

      let(:expected_error_class_name) { 'ParsingErrors::DependenciesNotPresentError' }
      let(:expected_error_message) { 'dependencies not present' }
    end
  end

  context 'when the file requires only indirect dependencies' do
    it_behaves_like 'parsing an invalid dependency config file' do
      let(:invalid_config_file_content) do
        <<~CONTENT
          module github.com/my-mod/my-mod

          require github.com/kr/text v0.2.0 // indirect
        CONTENT
      end
    end
  end

  describe '.matches?' do
    using RSpec::Parameterized::TableSyntax

    where(:path, :matches) do
      'go.mod'            | true
      'dir/go.mod'        | true
      'dir/subdir/go.mod' | true
      'dir/go'            | false
      'xgo.mod'           | false
      'Go.mod'            | false
      'go_mod'            | false
      'go'                | false
    end

    with_them do
      it 'matches the file name glob pattern at various directory levels' do
        expect(described_class.matches?(path)).to eq(matches)
      end
    end
  end
end
