# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::FeatureFlagsHelper, feature_category: :feature_flags do
  include Devise::Test::ControllerHelpers

  let(:project) { build_stubbed(:project) }
  let(:feature_flag) { build_stubbed(:operations_feature_flag, project: project, iid: 1) }
  let(:user) { build_stubbed(:user) }

  before do
    stub_licensed_features(feature_flags_code_references: feature_flags_code_references?)
    allow(helper).to receive(:can?).with(user, :admin_feature_flags_issue_links, project).and_return(admin_feature_flags_issue_links?)
    allow(helper).to receive(:current_user).and_return(user)

    self.instance_variable_set(:@project, project)
    self.instance_variable_set(:@feature_flag, feature_flag)
  end

  describe "#edit_feature_flags_data" do
    subject { helper.edit_feature_flag_data }

    context 'with permissions' do
      let(:admin_feature_flags_issue_links?) { true }
      let(:feature_flags_code_references?) { true }

      it 'adds the search path' do
        is_expected.to include(search_path: "/search?project_id=#{project.id}&scope=blobs&search=#{feature_flag.name}")
      end

      it 'adds the issue links path' do
        is_expected.to include(feature_flag_issues_endpoint: "/#{project.full_path}/-/feature_flags/#{feature_flag.iid}/issues")
      end
    end

    context 'without permissions' do
      let(:admin_feature_flags_issue_links?) { false }
      let(:feature_flags_code_references?) { false }

      it 'adds a blank search path' do
        is_expected.to include(search_path: '')
      end

      it 'adds a blank issue links path' do
        is_expected.to include(feature_flag_issues_endpoint: '')
      end
    end
  end
end
