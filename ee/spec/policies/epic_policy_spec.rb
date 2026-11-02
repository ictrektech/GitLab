# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EpicPolicy, feature_category: :portfolio_management do
  include ExternalAuthorizationServiceHelpers

  let_it_be(:user) { create(:user) }

  subject { described_class.new(user, epic) }

  shared_examples 'can comment on epics' do
    it { is_expected.to be_allowed(:create_note, :award_emoji) }
  end

  shared_examples 'cannot comment on epics' do
    it { is_expected.to be_disallowed(:create_note, :award_emoji) }
  end

  shared_examples 'can edit epic comments' do
    it { is_expected.to be_allowed(:admin_note) }
  end

  shared_examples 'cannot edit epic comments' do
    it { is_expected.to be_disallowed(:admin_note) }
  end

  shared_examples 'can admin epic relations' do
    it 'allows administering epic, tree, and link relations and reading epic and link relations' do
      is_expected.to be_allowed(
        :admin_epic_relation,
        :read_epic_relation,
        :admin_epic_tree_relation,
        :admin_epic_link_relation,
        :read_epic_link_relation
      )
    end
  end

  shared_examples 'cannot admin epic relations' do
    it 'disallows administering epic and epic tree relations' do
      is_expected.to be_disallowed(
        :admin_epic_relation,
        :admin_epic_tree_relation
      )
    end
  end

  shared_examples 'can only read epics' do
    it 'matches expected permissions' do
      is_expected.to be_allowed(
        :read_epic, :read_issuable, :read_epic_iid, :read_note,
        :create_todo, :read_issuable_participables
      )
      is_expected.to be_disallowed(
        :update_epic, :destroy_epic, :admin_epic,
        :create_epic, :set_epic_metadata, :set_confidentiality,
        :mark_note_as_internal, :read_internal_note
      )
    end
  end

  shared_examples 'can manage epics' do
    it 'matches expected permissions' do
      is_expected.to be_allowed(
        :read_epic, :read_issuable, :read_epic_iid, :read_note,
        :read_issuable_participables, :read_internal_note,
        :update_epic, :admin_epic, :create_epic, :admin_epic_relation,
        :create_todo, :admin_epic_link_relation, :set_epic_metadata,
        :set_confidentiality, :mark_note_as_internal,
        :admin_epic_tree_relation
      )
    end
  end

  shared_examples 'all epic permissions disabled' do
    it 'matches expected permissions' do
      is_expected.to be_disallowed(
        :read_epic, :read_issuable, :read_epic_iid, :update_epic,
        :destroy_epic, :admin_epic, :create_epic,
        :create_note, :award_emoji, :read_note,
        :read_issuable_participables,
        :create_todo, :admin_epic_link_relation,
        :set_epic_metadata, :set_confidentiality,
        :admin_epic_relation, :read_epic_relation,
        :admin_epic_tree_relation, :read_epic_link_relation,
        :create_epic_tree_relation
      )
    end
  end

  shared_examples 'all reporter epic permissions enabled' do
    it 'matches expected permissions' do
      is_expected.to be_allowed(
        :read_epic, :read_issuable, :read_epic_iid, :update_epic,
        :admin_epic, :create_epic, :create_note,
        :award_emoji, :read_note, :create_todo,
        :read_issuable_participables, :read_internal_note,
        :admin_epic_link_relation, :set_epic_metadata,
        :set_confidentiality, :admin_epic_relation,
        :admin_epic_tree_relation
      )
    end
  end

  shared_examples 'group member permissions' do
    context 'guest group member' do
      before do
        group.add_guest(user)
      end

      it_behaves_like 'can only read epics'
      it_behaves_like 'can comment on epics'
      it_behaves_like 'cannot edit epic comments'
      it_behaves_like 'can admin epic relations'
    end

    context 'planner group member' do
      before do
        group.add_planner(user)
      end

      it_behaves_like 'can manage epics'
      it_behaves_like 'can comment on epics'
      it_behaves_like 'cannot edit epic comments'

      it 'can destroy epics' do
        is_expected.to be_allowed(:destroy_epic)
      end
    end

    context 'reporter group member' do
      before do
        group.add_reporter(user)
      end

      it_behaves_like 'can manage epics'
      it_behaves_like 'can comment on epics'
      it_behaves_like 'cannot edit epic comments'

      it 'cannot destroy epics' do
        is_expected.to be_disallowed(:destroy_epic)
      end
    end

    context 'group maintainer' do
      before do
        group.add_maintainer(user)
      end

      it_behaves_like 'can manage epics'
      it_behaves_like 'can comment on epics'
      it_behaves_like 'can edit epic comments'

      it 'cannot destroy epics' do
        is_expected.to be_disallowed(:destroy_epic)
      end
    end

    context 'group owner' do
      before do
        group.add_owner(user)
      end

      it_behaves_like 'can manage epics'
      it_behaves_like 'can comment on epics'
      it_behaves_like 'can edit epic comments'

      it 'can destroy epics' do
        is_expected.to be_allowed(:destroy_epic)
      end
    end
  end

  context 'when epics feature is disabled' do
    let_it_be(:group) { create(:group, :public, owners: user) }
    let_it_be(:epic) { create(:epic, group: group) }

    it_behaves_like 'all epic permissions disabled'
  end

  context 'when epics features are enabled' do
    before do
      stub_licensed_features(epics: true, related_epics: true, subepics: true)
    end

    context 'when an epic is in a private group' do
      let_it_be(:group) { create(:group, :private) }
      let_it_be(:epic) { create(:epic, group: group) }

      context 'anonymous user' do
        let(:user) { nil }

        it_behaves_like 'all epic permissions disabled'
      end

      context 'user who is not a group member' do
        it_behaves_like 'all epic permissions disabled'
      end

      it_behaves_like 'group member permissions'
    end

    context 'when an epic is in an internal group' do
      let_it_be(:group) { create(:group, :internal) }
      let_it_be(:epic) { create(:epic, group: group) }

      context 'anonymous user' do
        let(:user) { nil }

        it_behaves_like 'all epic permissions disabled'
      end

      context 'user who is not a group member' do
        it_behaves_like 'can only read epics'
        it_behaves_like 'can comment on epics'
        it_behaves_like 'cannot admin epic relations'

        it 'matches expected permissions' do
          is_expected.to be_disallowed(:read_epic_link_relation, :read_epic_relation, :create_epic_tree_relation)
        end
      end
    end

    context 'when an epic is in a public group' do
      let_it_be(:group) { create(:group, :public) }
      let_it_be(:epic) { create(:epic, group: group) }

      context 'anonymous user' do
        let(:user) { nil }

        it 'matches expected permissions' do
          is_expected.to be_allowed(
            :read_epic, :read_issuable, :read_epic_iid, :read_note, :read_issuable_participables
          )

          is_expected.to be_disallowed(
            :create_todo, :read_internal_note, :admin_epic_tree_relation
          )
        end

        it_behaves_like 'cannot comment on epics'
        it_behaves_like 'cannot admin epic relations'
      end

      context 'user who is not a group member' do
        it_behaves_like 'can only read epics'
        it_behaves_like 'can comment on epics'
        it_behaves_like 'cannot admin epic relations'

        it 'matches expected permissions' do
          is_expected.to be_disallowed(:read_epic_link_relation, :read_epic_relation, :create_epic_tree_relation)
        end
      end
    end

    context 'when external authorization is enabled' do
      let_it_be(:group) { create(:group, owners: user) }
      let_it_be(:epic) { create(:epic, group: group) }

      before do
        enable_external_authorization_service_check
      end

      it 'does not call external authorization service' do
        expect(::Gitlab::ExternalAuthorization).not_to receive(:access_allowed?)

        subject
      end

      it_behaves_like 'all epic permissions disabled'
    end

    context 'when epic is confidential' do
      let_it_be_with_refind(:group) { create(:group) }
      let_it_be_with_refind(:epic) { create(:epic, group: group, confidential: true) }

      context 'when user is not reporter' do
        before_all do
          group.add_guest(user)
        end

        it_behaves_like 'all epic permissions disabled'
      end

      context 'when user is planner' do
        before_all do
          group.add_planner(user)
        end

        it_behaves_like 'all reporter epic permissions enabled'
      end

      context 'when user is reporter' do
        before_all do
          group.add_reporter(user)
        end

        it_behaves_like 'all reporter epic permissions enabled'
      end

      context 'when user is owner' do
        before_all do
          group.add_owner(user)
        end

        it_behaves_like 'all reporter epic permissions enabled'
      end

      context 'user is support bot' do
        let_it_be(:user) { create(:support_bot) }

        before do
          allow(::ServiceDesk).to receive(:supported?).and_return(true)
        end

        context 'when group has at least one project with service desk enabled' do
          let_it_be(:project_with_service_desk) do
            create(:project, group: group, service_desk_enabled: true)
          end

          it 'matches expected permissions' do
            is_expected.to be_allowed(:read_epic, :read_issuable, :read_epic_iid)
            is_expected.to be_disallowed(
              :update_epic, :destroy_epic, :admin_epic,
              :create_epic, :set_epic_metadata, :set_confidentiality,
              :mark_note_as_internal, :read_internal_note,
              :admin_epic_tree_relation
            )
          end
        end

        context 'when group does not have projects with service desk enabled' do
          let_it_be(:project_without_service_desk) do
            create(:project, group: group, service_desk_enabled: false)
          end

          it_behaves_like 'all epic permissions disabled'
        end
      end
    end

    context 'when epic is locked' do
      let_it_be(:group) { create(:group, :public) }
      let_it_be(:epic) do
        create(:work_item, :epic_with_legacy_epic, namespace: group, discussion_locked: true).synced_epic
      end

      context 'user who is not a group member' do
        it_behaves_like 'cannot comment on epics'
        it_behaves_like 'cannot edit epic comments'
      end

      context 'user who is guest' do
        before_all do
          group.add_guest(user)
        end

        it_behaves_like 'can comment on epics'
        it_behaves_like 'cannot edit epic comments'
      end

      context 'when user is planner' do
        before_all do
          group.add_planner(user)
        end

        it_behaves_like 'can comment on epics'
        it_behaves_like 'cannot edit epic comments'
      end

      context 'user who is reporter' do
        before_all do
          group.add_reporter(user)
        end

        it_behaves_like 'can comment on epics'
        it_behaves_like 'cannot edit epic comments'
      end

      context 'when user is maintainer' do
        before_all do
          group.add_maintainer(user)
        end

        it_behaves_like 'can comment on epics'
        it_behaves_like 'can edit epic comments'
      end
    end

    context 'when related_epics feature is not available' do
      let_it_be(:group) { create(:group, maintainers: user) }
      let_it_be(:epic) { create(:epic, group: group) }

      before do
        stub_licensed_features(epics: true, subepics: true)
      end

      it 'matches expected permissions' do
        is_expected.to be_allowed(
          :read_epic, :read_issuable, :read_epic_iid, :update_epic,
          :admin_epic, :create_epic, :create_note,
          :award_emoji, :read_note, :create_todo,
          :read_issuable_participables, :admin_epic_relation,
          :admin_epic_tree_relation, :create_epic_tree_relation
        )
        is_expected.to be_disallowed(:admin_epic_link_relation)
      end
    end

    context 'when subepics feature is not available' do
      let_it_be(:group) { create(:group, maintainers: user) }
      let_it_be(:epic) { create(:epic, group: group) }

      before do
        stub_licensed_features(epics: true, related_epics: true)
      end

      it 'matches expected permissions' do
        is_expected.to be_allowed(
          :read_epic, :read_issuable, :read_epic_iid, :update_epic,
          :admin_epic, :create_epic, :create_note,
          :award_emoji, :read_note, :create_todo,
          :read_issuable_participables, :admin_epic_relation,
          :admin_epic_link_relation
        )
        is_expected.to be_disallowed(:admin_epic_tree_relation, :create_epic_tree_relation)
      end
    end
  end

  describe 'set_epic_metadata' do
    let_it_be(:group) { create(:group) }
    let_it_be(:epic) { create(:epic, group: group) }

    before_all do
      group.add_reporter(user)
    end

    before do
      stub_licensed_features(epics: true)
    end

    it { expect_allowed(:set_epic_metadata) }

    context 'when the group is read only' do
      before do
        allow(epic.group).to receive(:read_only?).and_return(true)
      end

      it { expect_disallowed(:set_epic_metadata) }
    end
  end

  describe 'set_confidentiality' do
    let_it_be(:group) { create(:group) }
    let_it_be(:epic) { create(:epic, group: group) }

    before_all do
      group.add_reporter(user)
    end

    before do
      stub_licensed_features(epics: true)
    end

    it { expect_allowed(:set_confidentiality) }

    context 'when the group is read only' do
      before do
        allow(epic.group).to receive(:read_only?).and_return(true)
      end

      it { expect_disallowed(:set_confidentiality) }
    end
  end

  describe 'summarize_comments' do
    let_it_be(:group) { create(:group, :private) }
    let_it_be(:epic) { create(:epic, group: group) }

    subject { described_class.new(user, epic) }

    before do
      stub_licensed_features(epics: true)
    end

    context 'when user is nil' do
      let(:user) { nil }

      it { is_expected.to be_disallowed(:summarize_comments) }
    end

    context 'when user is logged in' do
      using RSpec::Parameterized::TableSyntax

      where(:authorizer_allowed, :can_read_epic, :expected) do
        true  | true  | :allowed
        true  | false | :disallowed
        false | true  | :disallowed
        false | false | :disallowed
      end

      with_them do
        let(:authorizer) { instance_double(::Gitlab::Llm::FeatureAuthorizer) }

        before do
          allow(::Gitlab::Llm::FeatureAuthorizer).to receive(:new).and_return(authorizer)
          allow(authorizer).to receive(:allowed?).and_return(authorizer_allowed)

          group.add_guest(user) if can_read_epic
        end

        it { is_expected.to public_send(:"be_#{expected}", :summarize_comments) }
      end

      context 'when verifying FeatureAuthorizer parameters' do
        let(:authorizer) { instance_double(::Gitlab::Llm::FeatureAuthorizer) }

        before_all do
          group.add_guest(user)
        end

        before do
          allow(::Gitlab::Llm::FeatureAuthorizer).to receive(:new).and_return(authorizer)
          allow(authorizer).to receive(:allowed?).and_return(true)
        end

        it 'creates FeatureAuthorizer with correct parameters' do
          expect(::Gitlab::Llm::FeatureAuthorizer).to receive(:new).with(
            container: group,
            feature_name: :summarize_comments,
            user: user
          ).and_return(authorizer)

          subject.allowed?(:summarize_comments)
        end
      end
    end
  end

  describe 'delegation' do
    it { expect(described_class).to delegate_to(GroupPolicy) }
  end
end
