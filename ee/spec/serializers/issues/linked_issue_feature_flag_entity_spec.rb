# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Issues::LinkedIssueFeatureFlagEntity do
  let(:project) { build_stubbed(:project) }
  let(:developer) { build_stubbed(:user) }

  describe '#as_json' do
    it 'returns json' do
      issue = build_stubbed(:issue, project: project)
      feature_flag = build_stubbed(:operations_feature_flag, project: project, iid: 1)
      link = build_stubbed(:feature_flag_issue, feature_flag: feature_flag, issue: issue)
      allow(issue).to receive(:link_id).and_return(link.id)
      request = double('request')
      allow(request).to receive_messages(current_user: developer, issuable: issue)
      entity = described_class.new(feature_flag, request: request, current_user: developer)

      expect(entity.as_json.slice(:link_type, :path, :reference)).to eq({
        link_type: 'relates_to',
        path: "/#{project.full_path}/-/feature_flags/#{feature_flag.iid}/edit",
        reference: "[feature_flag:#{feature_flag.iid}]"
      })
    end
  end
end
