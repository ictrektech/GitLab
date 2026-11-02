# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Context::Dependencies::ConfigFiles::PythonPip, feature_category: :code_suggestions do
  it 'returns the expected language value' do
    expect(described_class.lang).to eq('python')
  end

  it 'supports multiple files' do
    expect(described_class.supports_multiple_files?).to be(true)
  end

  describe '.matching_paths' do
    before do
      stub_const('Ai::Context::Dependencies::ConfigFiles::Base::MAX_MATCHING_FILES', 2)
    end

    it 'keeps the matching paths nearest the repository root, up to the cap' do
      paths = %w[dir/subdir/requirements.txt dir/requirements.txt z-requirements.txt requirements.txt README.md]

      expect(described_class.matching_paths(paths)).to eq(%w[requirements.txt z-requirements.txt])
    end
  end

  it_behaves_like 'parsing a valid dependency config file' do
    let(:config_file_content) do
      <<~CONTENT
        requests>=2.0,<3.0      # Version range
        numpy==1.26.4           # Exact version match
        python_dateutil>=2.5.3
        fastapi-health!=0.3.0

        # New supported formats
        pytest >= 2.6.4 ; python_version < '3.8'
        openpyxl == 3.1.2
        urllib3 @ https://github.com/path/main.zip
        requests [security] >= 2.8.1, == 2.8.*
        other-lib [extra-1,extra_2] == 2.1.0

        # Options
        -r other_requirements.txt
        -i https://pypi.org/simple
        --python-version 3
        --no-clean
        -e .
      CONTENT
    end

    let(:expected_formatted_lib_names) do
      [
        'requests (>=2.0,<3.0)',
        'numpy (==1.26.4)',
        'python_dateutil (>=2.5.3)',
        'fastapi-health (!=0.3.0)',
        'pytest (>= 2.6.4)',
        'openpyxl (== 3.1.2)',
        'urllib3',
        'requests (>= 2.8.1, == 2.8.*)',
        'other-lib (== 2.1.0)'
      ]
    end
  end

  it_behaves_like 'stopping at the library cap' do
    let(:config_file_content) do
      <<~CONTENT
        lib1==1.0
        lib2==2.0
        lib3==3.0
      CONTENT
    end

    let(:expected_formatted_lib_names) { ['lib1 (==1.0)', 'lib2 (==2.0)'] }
  end

  it_behaves_like 'parsing an invalid dependency config file' do
    let(:invalid_config_file_content) { '' }
    let(:expected_error_class_name) { 'ParsingErrors::FileEmptyError' }
    let(:expected_error_message) { 'file empty' }
  end

  describe '.matches?' do
    using RSpec::Parameterized::TableSyntax

    where(:path, :matches) do
      'requirements.txt'                | true
      'dir/requirements_other.txt'      | true
      'dir/subdir/dev-requirements.txt' | true
      'dir/requirements.c'              | false
      'test_requirements.txt'           | true
      'devrequirements.txt'             | true
      'Requirements.txt'                | false
      'requirements_txt'                | false
      'requirements'                    | false
    end

    with_them do
      it 'matches the file name glob pattern at various directory levels' do
        expect(described_class.matches?(path)).to eq(matches)
      end
    end
  end
end
