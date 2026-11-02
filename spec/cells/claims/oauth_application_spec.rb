# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Claim for Authn::OauthApplication', feature_category: :cell do
  let_it_be(:user) { create(:user) }

  subject! { build(:oauth_application, owner: user) }

  it_behaves_like 'creating new claims'
  it_behaves_like 'deleting existing claims'

  it_behaves_like 'updating existing claims' do
    let(:transform_attributes) { { uid: subject.uid.reverse } }
  end

  context 'when claims feature is disabled' do
    before do
      stub_feature_flags(cells_claims_oauth_applications: false)
    end

    it_behaves_like 'not creating claims'
    it_behaves_like 'not deleting claims'

    context 'when updating the record' do
      include_context 'with claiming tools'

      subject! { super().tap(&:save!) }

      it 'saves the record without invoking claiming logic' do
        expect_no_begin_update(:save)
        expect_no_commit_update
        expect_no_rollback_update

        expect(subject.update!(uid: SecureRandom.uuid)).to be(true) # rubocop:disable RSpec/NamedSubject -- subject is defined at the top level for the shared examples
        expect(Cells::OutstandingLease.count).to eq(0)
      end
    end
  end
end
