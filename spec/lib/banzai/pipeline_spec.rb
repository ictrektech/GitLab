# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Banzai::Pipeline, feature_category: :markdown do
  describe '.[]' do
    subject { described_class[name] }

    context 'for nil' do
      let(:name) { nil }

      it { is_expected.to eq(Banzai::Pipeline::FullPipeline) }
    end

    context 'for :full' do
      let(:name) { :full }

      it { is_expected.to eq(Banzai::Pipeline::FullPipeline) }
    end
  end
end
