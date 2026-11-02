# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ProjectIdParsing, feature_category: :vulnerability_management do
  let(:parser_class) do
    Class.new do
      include ::Security::ProjectIdParsing

      def call(ids)
        parse_project_ids(ids)
      end
    end
  end

  subject(:parse_project_ids) { parser_class.new.call(ids) }

  describe '#parse_project_ids' do
    context 'when ids is nil' do
      let(:ids) { nil }

      it { is_expected.to be_nil }
    end

    context 'when ids is empty' do
      let(:ids) { [] }

      it { is_expected.to be_nil }
    end

    context 'with GID strings' do
      let(:ids) { ['gid://gitlab/Project/1', 'gid://gitlab/Project/2'] }

      it { is_expected.to match_array([1, 2]) }
    end

    context 'with raw numeric strings' do
      let(:ids) { %w[1 2] }

      it { is_expected.to match_array([1, 2]) }
    end

    context 'with a mix of GID and numeric strings' do
      let(:ids) { ['gid://gitlab/Project/1', '2'] }

      it { is_expected.to match_array([1, 2]) }
    end

    context 'with GlobalID objects' do
      let(:ids) { [::Project.new(id: 1).to_global_id] }

      it { is_expected.to eq([1]) }
    end

    context 'with an unparseable value' do
      let(:ids) { ['not-a-valid-id'] }

      it 'drops the value' do
        is_expected.to eq([])
      end
    end
  end
end
