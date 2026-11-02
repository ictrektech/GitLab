# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PoliciesHelper, feature_category: :security_policy_management do
  let(:user) { build_stubbed(:user) }
  let(:group) { build_stubbed(:group) }
  let(:policy) { build_stubbed(:govern_policy, namespace: group, name: 'Require two approvals') }
  let(:scope) { group }

  let(:readable) { true }

  before do
    allow(helper).to receive(:current_user).and_return(user)
    allow(helper).to receive(:can?).with(user, :read_govern_policy, scope).and_return(readable)
  end

  describe '#govern_policy_store_path_for' do
    it 'points at the owning group' do
      expect(helper.govern_policy_store_path_for(policy))
        .to eq("/groups/#{group.full_path}/-/security/policy_store/#{policy.id}")
    end

    context 'when the policy has no namespace' do
      let(:policy) { build_stubbed(:govern_policy, :without_namespace, name: 'Org wide') }
      let(:scope) { policy.organization }

      it 'points at the owning organization' do
        expect(helper.govern_policy_store_path_for(policy))
          .to eq(security_policy_store_policy_organization_path(scope, policy.id))
      end
    end

    context 'when the user cannot read the policy' do
      let(:readable) { false }

      it 'returns nil rather than a link the user would 404 on' do
        expect(helper.govern_policy_store_path_for(policy)).to be_nil
      end
    end
  end

  describe '#govern_settings_locked_message' do
    subject(:message) { helper.govern_settings_locked_message(policy, settings) }

    let(:settings) { ['merge_requests_author_approval'] }

    it 'names the policy and links to it' do
      link = "<a href=\"/groups/#{group.full_path}/-/security/policy_store/#{policy.id}\">Require two approvals</a>"

      expect(message).to eq("The setting merge_requests_author_approval is locked by the policy #{link}.")
    end

    context 'with several settings' do
      let(:settings) { %w[merge_requests_author_approval allow_merge_on_skipped_pipeline] }

      it 'uses the plural form and lists them' do
        expect(message).to include(
          'The settings merge_requests_author_approval and allow_merge_on_skipped_pipeline are locked'
        )
      end
    end

    context 'when the user cannot read the policy' do
      let(:readable) { false }

      it 'still names the policy, without a link' do
        expect(message).to eq(
          'The setting merge_requests_author_approval is locked by the policy Require two approvals.'
        )
      end
    end

    context 'when the policy name contains markup' do
      let(:policy) { build_stubbed(:govern_policy, namespace: group, name: '<script>alert(1)</script>') }

      it 'escapes it' do
        expect(message).to include('&lt;script&gt;alert(1)&lt;/script&gt;')
        expect(message).not_to include('<script>')
      end
    end

    context 'with an authored block message' do
      subject(:message) do
        helper.govern_settings_locked_message(policy, settings, authored_message: authored_message)
      end

      let(:authored_message) { 'Ask the compliance team first.' }

      it 'leads with the authored message and still names the policy' do
        expect(message).to start_with('Ask the compliance team first. The setting')
        expect(message).to include('Require two approvals')
      end

      context 'when it contains markup' do
        let(:authored_message) { '<b>no</b>' }

        it 'escapes it' do
          expect(message).to include('&lt;b&gt;no&lt;/b&gt;')
        end
      end

      context 'when it is longer than the limit' do
        let(:authored_message) { 'a' * 1000 }

        it 'truncates it' do
          expect(message).to include("#{'a' * 497}...")
          expect(message).not_to include('a' * 501)
        end
      end

      context 'when it is blank' do
        let(:authored_message) { '' }

        it 'falls back to the attribution alone' do
          expect(message).to start_with('The setting merge_requests_author_approval is locked')
        end
      end
    end
  end
end
