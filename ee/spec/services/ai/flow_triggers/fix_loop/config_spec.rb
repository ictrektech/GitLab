# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::FixLoop::Config, feature_category: :dap_triggers do
  using RSpec::Parameterized::TableSyntax

  subject(:config) { described_class.new(content) }

  shared_examples 'a configuration with the defaults' do
    it 'applies the defaults', :aggregate_failures do
      expect(config).to be_valid
      expect(config.label).to be_nil
      expect(config.reviewer).to be_nil
      expect(config.max_fix_runs).to eq(3)
    end
  end

  describe '.for_project' do
    subject(:config) { described_class.for_project(project) }

    context 'with the file on the default branch' do
      let_it_be(:project) do
        create(:project, :custom_repo, files: { '.gitlab-dap-factory.yml' => "review:\n  max_fix_runs: 2\n" })
      end

      it 'reads the file' do
        expect(config.max_fix_runs).to eq(2)
      end
    end

    context 'without the file' do
      let_it_be(:project) { create(:project, :small_repo) }

      it_behaves_like 'a configuration with the defaults'
    end

    context 'with an empty repository' do
      let_it_be(:project) { create(:project, :empty_repo) }

      it_behaves_like 'a configuration with the defaults'
    end
  end

  describe '.new' do
    where(:case_name, :content) do
      'no file'              | nil
      'an empty file'        | ''
      'only comments'        | "# review:\n#   max_fix_runs: 2\n"
      'an empty document'    | "---\n"
      'no review key'        | "other:\n  key: value\n"
      'an empty review key'  | "review:\n"
      'keys without a value' | "review:\n  label:\n  reviewer:\n  max_fix_runs:\n"
    end

    with_them do
      it_behaves_like 'a configuration with the defaults'
    end

    context 'with all keys' do
      let(:content) { "review:\n  label: software-factory\n  reviewer: a-reviewer\n  max_fix_runs: 10\n" }

      it 'reads the keys', :aggregate_failures do
        expect(config).to be_valid
        expect(config.label).to eq('software-factory')
        expect(config.reviewer).to eq('a-reviewer')
        expect(config.max_fix_runs).to eq(10)
      end
    end

    context 'with a reviewer written as a mention' do
      let(:content) { "review:\n  reviewer: '@ GitLabDuo'\n" }

      it 'reads the username' do
        expect(config.reviewer).to eq('GitLabDuo')
      end
    end

    context 'with a blank label' do
      let(:content) { "review:\n  label: ' '\n" }

      it 'has no label', :aggregate_failures do
        expect(config).to be_valid
        expect(config.label).to be_nil
      end
    end

    context 'with an invalid key' do
      let(:fix_runs_error) { '`max_fix_runs` must be a number from 1 to 10.' }
      let(:unknown_keys) { "review:\n  max_rounds: 3\n  cap_round: true\n" }

      where(:case_name, :content, :error) do
        'a review list'        | "review: [1]\n"                   | '`review` must be a mapping.'
        'a label list'         | "review:\n  label: [a]\n"         | '`label` must be a string.'
        'a blank reviewer'     | "review:\n  reviewer: ' @'\n"     | '`reviewer` must be a username.'
        'a number reviewer'    | "review:\n  reviewer: 1\n"        | '`reviewer` must be a username.'
        'zero fix runs'        | "review:\n  max_fix_runs: 0\n"    | ref(:fix_runs_error)
        'too many fix runs'    | "review:\n  max_fix_runs: 11\n"   | ref(:fix_runs_error)
        'fix runs as a string' | "review:\n  max_fix_runs: '3'\n"  | ref(:fix_runs_error)
        'fractional fix runs'  | "review:\n  max_fix_runs: 2.5\n"  | ref(:fix_runs_error)
        'unknown keys'         | ref(:unknown_keys)                | 'Unknown keys: `max_rounds`, `cap_round`.'
        'an unknown odd key'   | "review:\n  '@all': 1\n"          | '`review` has unknown keys.'
        'invalid YAML'         | "review: {\n"                     | 'The file is not a valid YAML mapping.'
        'a top-level list'     | "- review\n"                      | 'The file is not a valid YAML mapping.'
      end

      with_them do
        it 'is not valid', :aggregate_failures do
          expect(config).not_to be_valid
          expect(config.errors).to include(error)
        end
      end
    end

    context 'with a review key that cannot be read' do
      where(:case_name, :content) do
        'invalid YAML'     | "review: {\n"
        'a top-level list' | "- review\n"
        'a review list'    | "review: [1]\n"
      end

      with_them do
        it 'has no values', :aggregate_failures do
          expect(config.label).to be_nil
          expect(config.reviewer).to be_nil
          expect(config.max_fix_runs).to be_nil
        end
      end
    end

    context 'with an invalid max_fix_runs only' do
      let(:content) { "review:\n  label: software-factory\n  reviewer: a-reviewer\n  max_fix_runs: 50\n" }

      it 'keeps the valid keys', :aggregate_failures do
        expect(config).not_to be_valid
        expect(config.label).to eq('software-factory')
        expect(config.reviewer).to eq('a-reviewer')
      end
    end
  end

  describe '#other_reviewer?' do
    context 'without a reviewer key' do
      let(:content) { nil }

      it 'matches the Duo Code Review bot by its type, whatever its username', :aggregate_failures do
        expect(config.other_reviewer?(build_stubbed(:user, :duo_code_review_bot, username: 'GitLabDuo_org')))
          .to be(false)
        expect(config.other_reviewer?(build_stubbed(:user, username: 'gitlabduo'))).to be(true)
      end
    end

    context 'with a reviewer key' do
      let(:content) { "review:\n  reviewer: GitLabDuo\n" }

      it 'matches the username of the reviewer in any case', :aggregate_failures do
        expect(config.other_reviewer?(build_stubbed(:user, username: 'gitlabduo'))).to be(false)
        expect(config.other_reviewer?(build_stubbed(:user, username: 'someone-else'))).to be(true)
      end
    end

    context 'with an invalid reviewer key' do
      let(:content) { "review:\n  reviewer: 1\n" }

      it 'counts no verdict as the verdict of another reviewer' do
        expect(config.other_reviewer?(build_stubbed(:user, username: 'someone-else'))).to be(false)
      end
    end

    context 'with a review key that cannot be read' do
      let(:content) { "review: {\n" }

      it 'counts no verdict as the verdict of another reviewer' do
        expect(config.other_reviewer?(build_stubbed(:user, username: 'someone-else'))).to be(false)
      end
    end
  end
end
