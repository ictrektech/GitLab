# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Notes::UnresolveService, feature_category: :code_review_workflow do
  let_it_be(:merge_request) { create(:merge_request) }
  let_it_be(:user) { merge_request.author }

  let(:note) { create(:diff_note_on_merge_request, noteable: merge_request, project: merge_request.project) }
  let(:service) { described_class.new(merge_request.project, user) }

  before do
    note.resolve!(user)
  end

  describe '#execute' do
    it 'unresolves the note' do
      service.execute(note)

      expect(note.reload).not_to be_resolved
    end

    context 'when the user is throttled' do
      before do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:discussions_resolve, hash_including(scope: { user: user })).and_return(true)
      end

      it 'raises an error without unresolving the note' do
        expect { service.execute(note) }.to raise_error(RateLimitedService::RateLimitedError)
        expect(note.reload).to be_resolved
      end
    end
  end
end
