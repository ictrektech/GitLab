# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PolicyHelpers, type: :policy, feature_category: :permissions do
  # read_build_report_results is enabled by `can?(:read_build) & can?(:read_pipeline)`.
  subject { ProjectPolicy.new(nil, build_stubbed(:project, :public)) }

  describe '#stub_permissions' do
    it 'decides the rules that check the stubbed permissions' do
      stub_permissions(read_build: true, read_pipeline: true)

      expect_allowed(:read_build_report_results)
    end

    it 'keeps permissions stubbed by an earlier call' do
      stub_permissions(read_build: false)
      stub_permissions(read_pipeline: true)

      expect_disallowed(:read_build_report_results)
    end

    it 'replaces results computed before the stub' do
      stub_permissions(read_build: true, read_pipeline: true)
      expect_allowed(:read_build_report_results)

      stub_permissions(read_pipeline: false)

      expect_disallowed(:read_build_report_results)
    end

    it 'raises for a permission the policy does not define' do
      expect { stub_permissions(read_cdoe: false) }
        .to raise_error(ArgumentError, 'ProjectPolicy does not define :read_cdoe')
    end
  end
end
