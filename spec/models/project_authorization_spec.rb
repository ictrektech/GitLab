# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProjectAuthorization, feature_category: :groups_and_projects do
  describe 'create' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project_1) { create(:project) }

    let(:project_auth) do
      build(
        :project_authorization,
        user: user,
        project: project_1
      )
    end

    it 'sets is_unique, overriding whatever the caller passed' do
      project_auth.is_unique = nil

      expect { project_auth.save! }.to change { project_auth.is_unique }.from(nil).to(true)
    end

    it 'writes is_unique into the INSERT rather than relying on the database default' do
      # The test schema already has the new default, so is_unique matches it in memory and
      # partial_inserts would drop the column from the INSERT. SafelyChangeColumnDefault
      # puts it back, which is what protects a process holding a stale schema cache.
      recorder = ActiveRecord::QueryRecorder.new { project_auth.save! }
      insert = recorder.log.find { |sql| sql.include?('INSERT INTO "project_authorizations"') }

      expect(insert).to include('is_unique')
      expect(project_auth.reload.is_unique).to be(true)
    end
  end

  describe 'unique user, project authorizations' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project_1) { create(:project) }

    let!(:project_auth) do
      create(
        :project_authorization,
        user: user,
        project: project_1,
        access_level: Gitlab::Access::DEVELOPER
      )
    end

    context 'with duplicate user and project authorization' do
      subject do
        project_auth.dup.tap do |auth|
          auth.project = project_1
          auth.user = user
        end
      end

      it { is_expected.to be_invalid }

      context 'after validation' do
        before do
          subject.valid?
        end

        it 'contains duplicate error' do
          expect(subject.errors[:user]).to include('has already been taken')
        end
      end
    end

    context 'with multiple access levels for the same user and project' do
      subject do
        project_auth.dup.tap do |auth|
          auth.project = project_1
          auth.user = user
          auth.access_level = Gitlab::Access::MAINTAINER
        end
      end

      it { is_expected.to be_invalid }

      context 'after validation' do
        before do
          subject.valid?
        end

        it 'contains duplicate error' do
          expect(subject.errors[:user]).to include('has already been taken')
        end
      end
    end
  end

  describe 'relations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:project) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:project) }
    it { is_expected.to validate_presence_of(:user) }
    it { is_expected.to validate_presence_of(:access_level) }
    it { is_expected.to validate_inclusion_of(:access_level).in_array(Gitlab::Access.all_values) }
  end

  describe 'scopes' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project, namespace: user.namespace) }

    describe '.non_guests' do
      let_it_be(:project_original_owner_authorization) { project.owner.project_authorizations.first }
      let_it_be(:project_authorization_guest) { create(:project_authorization, :guest, project: project) }
      let_it_be(:project_authorization_reporter) { create(:project_authorization, :reporter, project: project) }
      let_it_be(:project_authorization_developer) { create(:project_authorization, :developer, project: project) }
      let_it_be(:project_authorization_maintainer) { create(:project_authorization, :maintainer, project: project) }
      let_it_be(:project_authorization_owner) { create(:project_authorization, :owner, project: project) }

      it 'returns all records which are greater than Guests access' do
        expect(described_class.non_guests.map(&:attributes)).to match_array([
          project_authorization_reporter, project_authorization_developer,
          project_authorization_maintainer, project_authorization_owner,
          project_original_owner_authorization
        ].map(&:attributes))
      end
    end

    describe '.owners' do
      let_it_be(:project_original_owner_authorization) { project.owner.project_authorizations.first }
      let_it_be(:project_authorization_owner) { create(:project_authorization, :owner, project: project) }

      before_all do
        create(:project_authorization, :guest, project: project)
        create(:project_authorization, :developer, project: project)
      end

      it 'returns all records which only have Owners access' do
        expect(described_class.owners.map(&:attributes)).to match_array([
          project_original_owner_authorization,
          project_authorization_owner
        ].map(&:attributes))
      end
    end

    describe '.for_project' do
      let_it_be(:project_2) { create(:project, namespace: user.namespace) }
      let_it_be(:project_3) { create(:project, namespace: user.namespace) }

      let_it_be(:project_authorization_3) { project_3.project_authorizations.first }
      let_it_be(:project_authorization_2) { project_2.project_authorizations.first }
      let_it_be(:project_authorization) { project.project_authorizations.first }

      it 'returns all records for the project' do
        expect(described_class.for_project(project).map(&:attributes)).to match_array([
          project_authorization
        ].map(&:attributes))
      end

      it 'returns all records for multiple projects' do
        expect(described_class.for_project([project, project_3]).map(&:attributes)).to match_array([
          project_authorization,
          project_authorization_3
        ].map(&:attributes))
      end
    end

    describe '.for_user' do
      let_it_be(:user_1) { create(:user) }
      let_it_be(:user_2) { create(:user) }

      let_it_be(:project_1) { create(:project) }
      let_it_be(:project_2) { create(:project) }

      let_it_be(:project_auth_1) { create(:project_authorization, user: user_1, project: project_1) }
      let_it_be(:project_auth_2) { create(:project_authorization, user: user_1, project: project_2) }
      let_it_be(:project_auth_3) { create(:project_authorization, user: user_2, project: project_1) }
      let_it_be(:project_auth_4) { create(:project_authorization, user: user_2, project: project_2) }

      subject(:for_user) { described_class.for_user(user_1) }

      it 'returns all records for the user' do
        expect(for_user).to match_array([project_auth_1, project_auth_2])
      end
    end

    describe '.count_by_user_id' do
      subject(:count_by_user_id) { described_class.count_by_user_id }

      it 'returns the number of records grouped by user' do
        expect(count_by_user_id).to eq({ user.id => 1 })
      end
    end
  end

  describe '.project_ids_pending_own_refresh' do
    let_it_be(:old_project) { create(:project, created_at: 1.day.ago) }
    let_it_be(:new_project) { create(:project, created_at: 1.minute.ago) }
    let_it_be(:importing_project) { create(:project, :import_started, created_at: 1.day.ago) }
    let_it_be(:imported_project) { create(:project, :import_finished, created_at: 1.day.ago) }

    it 'returns the given projects created since the time or with an import in progress' do
      ids = [old_project, new_project, importing_project, imported_project].map(&:id)

      expect(described_class.project_ids_pending_own_refresh(ids, since: 10.minutes.ago))
        .to contain_exactly(new_project.id, importing_project.id)
    end

    it 'only considers the given projects' do
      expect(described_class.project_ids_pending_own_refresh([old_project.id], since: 10.minutes.ago)).to be_empty
    end
  end

  describe '.deleted_project_ids' do
    let_it_be(:project) { create(:project) }

    it 'returns the given ids that no longer have a project' do
      expect(described_class.deleted_project_ids([project.id, non_existing_record_id]))
        .to contain_exactly(non_existing_record_id)
    end

    it 'returns nothing when every project exists' do
      expect(described_class.deleted_project_ids([project.id])).to be_empty
    end
  end

  describe '.project_ids_and_access_levels_for' do
    let_it_be(:other_user) { create(:user) }
    let_it_be(:project_1) { create(:project) }
    let_it_be(:project_2) { create(:project) }

    let_it_be(:auth_1) do
      create(:project_authorization, user: other_user, project: project_1,
        access_level: Gitlab::Access::DEVELOPER)
    end

    let_it_be(:auth_2) do
      create(:project_authorization, user: other_user, project: project_2,
        access_level: Gitlab::Access::MAINTAINER)
    end

    it 'returns [project_id, access_level] pairs rather than records' do
      expect(described_class.project_ids_and_access_levels_for(other_user.id)).to match_array([
        [project_1.id, Gitlab::Access::DEVELOPER],
        [project_2.id, Gitlab::Access::MAINTAINER]
      ])
    end

    it 'only returns rows for the given user' do
      unrelated_user = create(:user)
      create(:project_authorization, user: unrelated_user, project: project_1)

      pairs = described_class.project_ids_and_access_levels_for(unrelated_user.id)

      expect(pairs.map(&:first)).to contain_exactly(project_1.id)
    end

    it 'returns an empty array for a user with no authorizations' do
      expect(described_class.project_ids_and_access_levels_for(non_existing_record_id)).to eq([])
    end
  end

  describe '.access_levels_by_project' do
    let_it_be(:other_user) { create(:user) }
    let_it_be(:other_project) { create(:project) }

    let_it_be(:authorization) do
      create(:project_authorization, user: other_user, project: other_project,
        access_level: Gitlab::Access::REPORTER)
    end

    let(:relation) do
      described_class.for_user(other_user.id).select(:project_id, :access_level)
    end

    it 'maps project IDs to access levels' do
      expect(described_class.access_levels_by_project(relation))
        .to eq({ other_project.id => Gitlab::Access::REPORTER })
    end

    it 'returns an empty hash when the relation matches nothing' do
      empty = described_class.for_user(non_existing_record_id).select(:project_id, :access_level)

      expect(described_class.access_levels_by_project(empty)).to eq({})
    end

    context 'when the relation does not select the expected columns' do
      it 'raises rather than mapping the wrong values' do
        wrong_order = described_class.for_user(other_user.id).select(:access_level, :project_id)

        expect { described_class.access_levels_by_project(wrong_order) }
          .to raise_error(ArgumentError, /expected project_id, access_level/)
      end
    end
  end

  describe '.insert_all' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project_1) { create(:project) }
    let_it_be(:project_2) { create(:project) }
    let_it_be(:project_3) { create(:project) }

    it 'skips duplicates and inserts the remaining rows without error' do
      create(:project_authorization, user: user, project: project_1, access_level: Gitlab::Access::MAINTAINER)

      attributes = [
        { user_id: user.id, project_id: project_1.id, access_level: Gitlab::Access::MAINTAINER, is_unique: true },
        { user_id: user.id, project_id: project_1.id, access_level: Gitlab::Access::DEVELOPER, is_unique: true },
        { user_id: user.id, project_id: project_2.id, access_level: Gitlab::Access::MAINTAINER, is_unique: true },
        { user_id: user.id, project_id: project_3.id, access_level: Gitlab::Access::MAINTAINER, is_unique: true }
      ]

      described_class.insert_all(attributes)

      expect(user.project_authorizations.pluck(:user_id, :project_id, :access_level)).to match_array([
        [user.id, project_1.id, Gitlab::Access::MAINTAINER],
        [user.id, project_2.id, Gitlab::Access::MAINTAINER],
        [user.id, project_3.id, Gitlab::Access::MAINTAINER]
      ])
    end

    # A row outside the partial unique index still conflicts on the primary key, the same
    # conflict a concurrent insert of an identical row hits.
    it 'skips rows that conflict on any unique index' do
      create(:project_authorization, user: user, project: project_1, access_level: Gitlab::Access::MAINTAINER)
        .update_column(:is_unique, false)

      attributes = [
        { user_id: user.id, project_id: project_1.id, access_level: Gitlab::Access::MAINTAINER, is_unique: true },
        { user_id: user.id, project_id: project_2.id, access_level: Gitlab::Access::MAINTAINER, is_unique: true }
      ]

      expect(described_class.insert_all(attributes).length).to eq(1)
      expect(user.project_authorizations.pluck(:project_id, :access_level, :is_unique)).to match_array([
        [project_1.id, Gitlab::Access::MAINTAINER, false],
        [project_2.id, Gitlab::Access::MAINTAINER, true]
      ])
    end

    it 'returns an empty result without querying when given no rows' do
      expect(described_class.connection).not_to receive(:exec_insert_all)

      expect(described_class.insert_all([])).to be_empty
    end

    it 'raises when rows have different keys' do
      attributes = [
        { user_id: user.id, project_id: project_1.id, access_level: Gitlab::Access::MAINTAINER },
        { user_id: user.id, project_id: project_2.id }
      ]

      expect { described_class.insert_all(attributes) }
        .to raise_error(ArgumentError, 'All rows must have the same keys')
    end

    # Pins the hand-written statement: no conflict target, so a conflict on any unique index is skipped
    it 'inserts with an ON CONFLICT clause that has no target' do
      attributes = [
        { user_id: user.id, project_id: project_1.id, access_level: Gitlab::Access::MAINTAINER, is_unique: true }
      ]

      expect(described_class.connection).to receive(:exec_insert_all).and_call_original

      recorder = ActiveRecord::QueryRecorder.new { described_class.insert_all(attributes) }

      columns = '"user_id","project_id","access_level"'

      expect(recorder.log).to include(
        a_string_starting_with(%(INSERT INTO "project_authorizations" (#{columns},"is_unique") VALUES))
          .and(a_string_including(%(ON CONFLICT DO NOTHING RETURNING #{columns})))
      )
    end
  end

  context 'with loose foreign key on project_authorizations.user_id' do
    it_behaves_like 'cleanup by a loose foreign key' do
      let_it_be(:parent) { create(:user) }
      let_it_be(:model) { create(:project_authorization, user: parent) }
    end
  end

  context 'with loose foreign key on project_authorizations.project_id' do
    it_behaves_like 'cleanup by a loose foreign key' do
      let_it_be(:parent) { create(:project) }
      let_it_be(:model) { create(:project_authorization, project: parent) }
    end
  end

  describe '.find_or_create_authorization_for' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user) }
    let_it_be(:user_id) { user.id }
    let_it_be(:project_id) { project.id }
    let(:access_level) { Gitlab::Access::OWNER }

    subject(:create_project_authorization_record) do
      described_class.find_or_create_authorization_for(user_id, project_id, access_level)
    end

    context 'when record already exists' do
      before_all do
        create(:project_authorization, :owner, project: project, user: user)
      end

      it 'returns existing record' do
        expect { create_project_authorization_record }.not_to change { described_class.count }
      end

      context 'with race condition handling of already existing record' do
        it 'performs the upsert without error' do
          expect(described_class).to receive(:find_by).and_return(nil)

          expect { create_project_authorization_record }.not_to change { described_class.count }
        end
      end
    end

    context 'when no existing record exists' do
      it 'creates a new record with default access_level' do
        expect { create_project_authorization_record }.to change { described_class.count }.by(1)
        expect(user.project_authorizations)
          .to contain_exactly(have_attributes(access_level: access_level, is_unique: true))
      end
    end
  end

  describe '.for_project_groups' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:user) { create(:user) }
    let_it_be(:project_authorization) do
      create(:project_authorization, user: user, project: project, access_level: Gitlab::Access::DEVELOPER)
    end

    it 'returns group id and user id for authorized project members' do
      result = described_class.for_project_groups([user.id])

      expect(result.map { |r| [r[:id], r.user_id] }).to contain_exactly([group.id, user.id])
    end

    context 'when organization is given' do
      let_it_be(:other_organization) { create(:organization) }

      it 'returns group id only for groups in the organization' do
        result = described_class.for_project_groups([user.id], organization: group.organization)
        expect(result.map { |r| [r[:id], r.user_id] }).to contain_exactly([group.id, user.id])

        empty_result = described_class.for_project_groups([user.id], organization: other_organization)
        expect(empty_result).to be_empty
      end
    end
  end
end
