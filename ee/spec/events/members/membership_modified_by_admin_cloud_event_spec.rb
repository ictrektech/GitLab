# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Members::MembershipModifiedByAdminCloudEvent, feature_category: :seat_cost_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:admin) { create(:admin) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:member) { create(:group_member, :developer, source: group) }

  describe '.build' do
    let(:current_user) { admin }
    let(:event) { described_class.build(member: member, current_user: current_user) }

    it 'sets event_type to :membership_modified_by_admin' do
      expect(event.event_type).to eq(:membership_modified_by_admin)
    end

    it 'sets event_category to :members' do
      expect(event.event_category).to eq(:members)
    end

    it 'includes only member_user_id in event data' do
      expect(event.event_data).to eq({ member_user_id: member.user_id })
    end

    it 'derives source, subject and organization from the member source' do
      expect(event.data[:source]).to eq("groups/#{group.id}")
      expect(event.data[:subject]).to eq("members/group/#{group.id}")
      expect(event.organization).to eq(organization)
    end

    it 'sets the acting user as the current_user' do
      expect(event.data[:gitlab_user_id]).to eq(admin.id)
      expect(event.data[:gitlab_user_username]).to eq(admin.username)
    end

    context 'when current_user is nil' do
      let(:current_user) { nil }

      it 'publishes without an actor rather than misattributing it' do
        expect(event.data[:gitlab_user_id]).to be_nil
        expect(event.data[:gitlab_user_username]).to be_nil
      end

      it 'still carries the member_user_id payload' do
        expect(event.event_data).to eq({ member_user_id: member.user_id })
      end
    end

    context 'when source is nil' do
      it 'raises an ArgumentError' do
        expect { described_class.build(member: member, current_user: admin, source: nil) }
          .to raise_error(ArgumentError, 'source is required')
      end
    end

    context 'when source is given explicitly' do
      let(:unloaded_member) { Member.find(member.id) }

      it 'builds the same event without querying for the member source' do
        # Warm up the organization association and instantiate the member record
        # so only the source lookup would show up in the recorder.
        described_class.build(member: member, current_user: admin, source: group)
        unloaded_member

        recorder = ActiveRecord::QueryRecorder.new do
          described_class.build(member: unloaded_member, current_user: admin, source: group)
        end

        expect(recorder.count).to eq(0)
      end

      it 'derives source and subject from the given source' do
        event = described_class.build(member: unloaded_member, current_user: admin, source: group)

        expect(event.data[:source]).to eq("groups/#{group.id}")
        expect(event.data[:subject]).to eq("members/group/#{group.id}")
      end
    end
  end

  it_behaves_like 'a cloud event with schema',
    valid_data: { member_user_id: 1 },
    missing_required: %i[member_user_id],
    invalid_types: { member_user_id: 'not_an_integer' }
end
