# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TodoPolicy, feature_category: :notifications do
  include PolicyHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :private) }
  let_it_be(:saml_provider) { create(:saml_provider, group: group, enabled: true, enforced_sso: true) }

  subject { described_class.new(user, todo) }

  before do
    stub_licensed_features(group_saml: true, epics: true)
  end

  # Run inside a web session that has never recorded a group SAML sign-in, so the
  # group's SAML session reads as expired and SsoEnforcer.access_restricted?
  # returns true.
  around do |example|
    session = { 'warden.user.user.key' => [[user.id], user.authenticatable_salt] }
    Gitlab::Session.with_session(session) { example.run }
  end

  describe 'read_todo when the target is behind an expired group SAML session' do
    context 'when the user could read the target after reauthenticating' do
      let_it_be(:project) { create(:project, :private, group: group, developers: user) }
      let_it_be(:issue) { create(:issue, project: project) }
      let_it_be(:todo) { create(:todo, user: user, project: project, target: issue) }

      it 'is hidden by the group SAML session but readable once it is restored' do
        expect(issue.readable_by?(user)).to be(false)
        expect(::Gitlab::Auth::GroupSaml::SsoEnforcer.bypassing_enforcement { issue.readable_by?(user) }).to be(true)
      end

      it 'keeps the to-do readable so it can be shown masked' do
        expect_allowed(:read_todo)
      end

      context 'when the to-do belongs to another user' do
        subject { described_class.new(create(:user), todo) }

        it 'is not readable' do
          expect_disallowed(:read_todo)
        end
      end

      context 'when the to-do is group-scoped' do
        let_it_be(:group) { create(:group, :private, developers: user) }
        let_it_be(:saml_provider) { create(:saml_provider, group: group, enabled: true, enforced_sso: true) }
        let_it_be(:epic) { create(:epic, group: group) }
        let_it_be(:todo) { create(:todo, user: user, group: group, target: epic) }

        it 'resolves the resource from the group and keeps the to-do readable so it can be shown masked' do
          expect(todo.project).to be_nil
          expect_allowed(:read_todo)
        end
      end

      context 'when the target is a commit' do
        let_it_be(:project) { create(:project, :repository, :private, group: group, developers: user) }
        let_it_be(:todo) { create(:on_commit_todo, user: user, project: project, author: user) }

        it 'resolves :read_commit and keeps the to-do readable so it can be shown masked' do
          expect(todo).to be_for_commit
          expect_allowed(:read_todo)
        end
      end
    end

    context 'when the user cannot read the target even after reauthenticating' do
      context 'when the target is confidential and they are only a guest' do
        let_it_be(:project) { create(:project, :private, group: group, guests: user) }
        let_it_be(:issue) { create(:issue, :confidential, project: project) }
        let_it_be(:todo) { create(:todo, user: user, project: project, target: issue) }

        it 'stays hidden even with the SAML session restored' do
          expect(::Gitlab::Auth::GroupSaml::SsoEnforcer.bypassing_enforcement { issue.readable_by?(user) }).to be(false)
        end

        it 'is not readable' do
          expect_disallowed(:read_todo)
        end
      end

      context 'when they are no longer a member' do
        let_it_be(:project) { create(:project, :private, group: group) }
        let_it_be(:issue) { create(:issue, project: project) }
        let_it_be(:todo) { create(:todo, user: user, project: project, target: issue) }

        it 'is not readable' do
          expect_disallowed(:read_todo)
        end
      end

      context 'when the target no longer exists' do
        let_it_be(:project) { create(:project, :private, group: group, developers: user) }
        let_it_be(:todo) { create(:on_commit_todo, user: user, project: project, author: user) }

        it 'is not readable' do
          expect(todo.target).to be_nil
          expect_disallowed(:read_todo)
        end
      end
    end
  end

  describe 'read_todo for an internal-note to-do behind an expired group SAML session' do
    context 'when the user could read the internal note after reauthenticating' do
      let_it_be(:project) { create(:project, :private, group: group, developers: user) }
      let_it_be(:issue) { create(:issue, project: project) }
      let_it_be(:internal_note) { create(:note, :confidential, project: project, noteable: issue) }
      let_it_be(:todo) { create(:todo, user: user, project: project, target: issue, note: internal_note) }

      it 'keeps the to-do readable so it can be shown masked' do
        expect_allowed(:read_todo)
      end
    end

    context 'when the user cannot read the internal note even after reauthenticating' do
      let_it_be(:project) { create(:project, :private, group: group, guests: user) }
      let_it_be(:issue) { create(:issue, project: project) }
      let_it_be(:internal_note) { create(:note, :confidential, project: project, noteable: issue) }
      let_it_be(:todo) { create(:todo, user: user, project: project, target: issue, note: internal_note) }

      it 'stays hidden' do
        expect_disallowed(:read_todo)
      end
    end

    context 'when the target no longer exists' do
      let_it_be(:project) { create(:project, :private, group: group, developers: user) }
      let_it_be(:internal_note) { create(:note, :confidential, project: project) }
      let_it_be(:todo) do
        create(:on_commit_todo, user: user, project: project, author: user, note: internal_note)
      end

      it 'stays hidden' do
        expect(todo.target).to be_nil
        expect_disallowed(:read_todo)
      end
    end
  end
end
