# frozen_string_literal: true

require 'spec_helper'

RSpec.describe IssuePolicy, feature_category: :team_planning do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:admin, freeze: false) { create(:user, :admin) }
  let_it_be(:user, freeze: false) { create(:user) }
  let_it_be(:guest, freeze: false) { create(:user) }
  let_it_be(:planner, freeze: false) { create(:user) }
  let_it_be(:reporter, freeze: false) { create(:user) }
  let_it_be(:owner, freeze: false) { create(:user) }
  let_it_be(:non_member) { create(:user) }
  let_it_be_with_refind(:project) { create(:project, :private) }
  let_it_be_with_refind(:issue) { create(:issue, project: project) }

  let_it_be(:root_group, freeze: false) do
    create(:group, :public).tap do |g|
      g.add_planner(planner)
      g.add_reporter(reporter)
      g.add_owner(owner)
    end
  end

  let_it_be(:group, freeze: false) do
    create(:group, :public, parent: root_group).tap do |g|
      g.add_guest(guest)
      g.add_planner(planner)
      g.add_reporter(reporter)
      g.add_owner(owner)
    end
  end

  let_it_be(:support_bot, freeze: false) { create(:support_bot) }

  subject(:policy) { described_class.new(user, issue) }

  def add_members(project)
    project.add_guest(guest)
    project.add_planner(planner)
    project.add_reporter(reporter)
    project.add_owner(owner)
  end

  describe 'summarize_comments', :with_cloud_connector do
    let(:authorizer) { instance_double(::Gitlab::Llm::FeatureAuthorizer) }

    context 'when user is nil' do
      let(:user) { nil }
      let_it_be_with_refind(:project) { create(:project, :public) }

      before do
        allow(::Gitlab::Llm::FeatureAuthorizer).to receive(:new).and_return(authorizer)
      end

      it { expect_disallowed(:summarize_comments, :generate_description) }
    end

    context 'when user is logged in' do
      before do
        allow(::Gitlab::Llm::FeatureAuthorizer).to receive(:new).and_return(authorizer)
        allow(project).to receive(:duo_features_enabled).and_return(true)
      end

      context "when feature is authorized" do
        before do
          allow(authorizer).to receive(:allowed?).and_return(true)
        end

        context 'when user can read issue' do
          before_all do
            project.add_guest(user)
          end

          it { expect_allowed(:summarize_comments) }

          context 'when feature is not enabled' do
            before do
              allow(authorizer).to receive(:allowed?).and_return(false)
            end

            it { expect_disallowed(:summarize_comments) }
          end
        end

        context 'when user cannot read issue' do
          it { expect_disallowed(:summarize_comments) }

          context 'with confidential issue' do
            let_it_be(:confidential_issue, freeze: false) { create(:issue, :confidential, project: project) }
            let(:issue) { confidential_issue }

            before_all do
              project.add_guest(guest)
              project.add_planner(planner)
            end

            context 'as a guest' do
              let(:user) { guest }

              it { expect_disallowed(:read_issue, :summarize_comments) }
            end

            context 'as a planner' do
              let(:user) { planner }

              it { expect_allowed(:read_issue, :summarize_comments) }
            end
          end
        end
      end

      context "when feature is not authorized" do
        before_all do
          project.add_guest(user)
        end

        before do
          allow(authorizer).to receive(:allowed?).and_return(false)
        end

        it { expect_disallowed(:summarize_comments) }
      end
    end
  end

  describe 'reopen_issue for group level issue' do
    let_it_be_with_reload(:group_issue) { create(:issue, :group_level, namespace: group) }
    let(:issue) { group_issue }

    where(:user, :epics_licensed, :allowed) do
      ref(:non_member) | false | false
      nil              | false | false
      ref(:guest)      | false | false
      ref(:reporter)   | false | false
      ref(:planner)    | false | false
      ref(:owner)      | false | false
      ref(:guest)      | true  | false
      ref(:reporter)   | true  | true
      ref(:planner)    | true  | true
      ref(:owner)      | true  | true
    end

    with_them do
      before do
        stub_licensed_features(epics: epics_licensed)
      end

      it { allowed ? expect_allowed(:reopen_issue) : expect_disallowed(:reopen_issue) }
    end
  end

  describe 'admin_issue_relation' do
    let_it_be_with_reload(:group_issue) { create(:issue, :group_level, namespace: group) }
    let_it_be(:public_project, freeze: false) { create(:project, :public, group: group) }
    let_it_be(:private_project, freeze: false) { create(:project, :private, group: group) }
    let_it_be(:public_issue, freeze: false) { create(:issue, project: public_project) }
    let_it_be(:private_issue, freeze: false) { create(:issue, project: private_project) }

    where(:user, :issue, :allowed) do
      ref(:non_member) | ref(:public_issue)  | true
      ref(:non_member) | ref(:group_issue)   | false
      ref(:non_member) | ref(:private_issue) | false
      ref(:guest)      | ref(:group_issue)   | false
      ref(:guest)      | ref(:private_issue) | true
      ref(:guest)      | ref(:public_issue)  | true
    end

    with_them do
      it { allowed ? expect_allowed(:admin_issue_relation) : expect_disallowed(:admin_issue_relation) }
    end

    context 'with group level issue license' do
      let(:user) { guest }
      let(:issue) { group_issue }

      before do
        stub_licensed_features(epics: true)
      end

      it { expect_allowed(:admin_issue_relation) }
    end

    context 'when issue is confidential' do
      let_it_be(:confidential_issue, freeze: false) { create(:issue, :confidential, project: public_project) }
      let(:issue) { confidential_issue }

      context 'as a guest' do
        let(:user) { guest }

        it { expect_disallowed(:admin_issue_relation) }
      end

      context 'as a reporter' do
        let(:user) { reporter }

        it { expect_allowed(:admin_issue_relation) }
      end
    end

    context 'when user is support bot' do
      let(:user) { support_bot }

      context 'when service desk is enabled' do
        before do
          allow(::Gitlab::Email::IncomingEmail).to receive_messages(enabled?: true, supports_wildcard?: true)
          allow(::ServiceDesk).to receive(:enabled?).and_return(true)
        end

        where(:issue, :allowed) do
          ref(:public_issue)  | true
          ref(:private_issue) | true
        end

        with_them do
          it { allowed ? expect_allowed(:admin_issue_relation) : expect_disallowed(:admin_issue_relation) }
        end

        context 'on a group issue' do
          let(:issue) { group_issue }

          it { expect_disallowed(:admin_issue_relation, :read_issue) }

          context 'with group level issue license' do
            before do
              stub_licensed_features(epics: true)
            end

            it { expect_allowed(:admin_issue_relation, :read_issue) }
          end
        end
      end

      context 'when service desk is disabled' do
        context 'on a public project issue' do
          let(:issue) { public_issue }

          it { expect_disallowed(:admin_issue_relation) }
        end

        context 'on a private project issue' do
          let(:issue) { private_issue }

          it { expect_disallowed(:admin_issue_relation) }
        end

        context 'on a group issue' do
          let(:issue) { group_issue }

          it { expect_disallowed(:admin_issue_relation, :read_issue) }
        end
      end
    end

    context 'when issue has a synced epic' do
      let_it_be_with_reload(:group_issue) { create(:issue, :with_synced_epic, namespace: group) }
      let(:issue) { group_issue }

      before do
        stub_licensed_features(issuable_resource_links: true, epics: true)
      end

      context 'without group level issue license' do
        before do
          stub_licensed_features(epics: false)
        end

        context 'as a guest' do
          let(:user) { guest }

          it 'does not allow reading the issue' do
            expect_disallowed(
              :read_issue, :read_issuable, :admin_issue_link, :read_issuable_participables, :read_note, :read_work_item,
              :read_issuable_metric_image, :read_timeline_event, :read_cross_project
            )
          end
        end

        %i[planner reporter].each do |role|
          context "as a #{role}" do
            let(:user) { public_send(role) }

            it { expect_disallowed(:read_internal_note, :read_crm_contacts) }
          end
        end

        context 'as an owner' do
          let(:user) { owner }

          it 'does not allow permissions that modify the issue' do
            expect_disallowed(
              :admin_issue, :update_issue, :set_issue_metadata, :create_note, :admin_issue_relation, :award_emoji,
              :create_todo, :update_subscription, :set_confidentiality, :set_issue_crm_contacts, :set_note_created_at,
              :mark_note_as_internal, :create_timelog, :destroy_issue, :admin_note,
              :move_issue, :clone_issue
            )
          end

          it 'does not allow permissions not yet defined for group level issues' do
            expect_disallowed(
              :read_issuable_resource_link, :read_issue_iid, :read_design,
              :reposition_note, :create_design, :update_design, :destroy_design, :move_design,
              :upload_issuable_metric_image, :update_issuable_metric_image, :delete_issuable_metric_image,
              :admin_issuable_resource_link, :admin_timelog
            )
          end
        end
      end

      context 'with group level issue license' do
        before do
          stub_licensed_features(epics: true)
        end

        context 'as a guest' do
          let(:user) { guest }

          it 'allows reading the issue' do
            expect_allowed(
              :read_issue, :read_issuable, :admin_issue_link, :read_issuable_participables, :read_note, :read_work_item,
              :read_timeline_event, :read_cross_project
            )
          end
        end

        %i[planner reporter].each do |role|
          context "as a #{role}" do
            let(:user) { public_send(role) }

            it { expect_allowed(:read_internal_note, :read_crm_contacts) }
          end
        end

        context 'as an owner' do
          let(:user) { owner }

          it 'allows permissions that modify the issue' do
            expect_allowed(
              :admin_issue, :update_issue, :set_issue_metadata, :create_note, :admin_issue_relation, :award_emoji,
              :create_todo, :update_subscription, :set_confidentiality, :set_issue_crm_contacts, :set_note_created_at,
              :mark_note_as_internal, :create_timelog, :admin_timelog, :destroy_issue, :admin_note
            )
          end

          # This group issue is actually an epic work item, and for now we only allow move and clone for:
          # Issue, Incident and Test Case, see Issue#supports_move_and_clone?
          it { expect_disallowed(:move_issue, :clone_issue) }

          it 'does not allow metric images, which are only available on incidents' do
            expect_disallowed(
              :read_issuable_metric_image, :upload_issuable_metric_image, :update_issuable_metric_image,
              :delete_issuable_metric_image
            )
          end

          it 'does not allow permissions not yet defined for group level issues' do
            expect_disallowed(
              :read_issuable_resource_link, :read_issue_iid, :read_design,
              :reposition_note, :create_design, :update_design, :destroy_design, :move_design,
              :admin_issuable_resource_link
            )
          end
        end
      end

      context 'when external authorization is enabled' do
        include ExternalAuthorizationServiceHelpers

        before do
          enable_external_authorization_service_check
        end

        %i[guest reporter owner].each do |role|
          context "as a #{role}" do
            let(:user) { public_send(role) }

            it { expect_disallowed(:read_issue, :read_note) }
          end
        end

        context 'as an anonymous user' do
          let(:user) { nil }

          it { expect_disallowed(:read_issue) }
        end

        context 'as an admin with read_all_resources', :enable_admin_mode do
          let(:user) { admin }

          it { expect_allowed(:read_issue) }
        end

        context 'on an issue with no synced epic' do
          let(:user) { reporter }
          let(:issue) { create(:issue, project: create(:project, group: group)) }

          it { expect_allowed(:read_issue) }
        end
      end
    end
  end

  context 'when work item type is incident' do
    let_it_be(:incident_project) { create(:project, :private) }
    let_it_be(:incident) { create(:incident, project: incident_project) }
    let_it_be(:guest_incident) { create(:incident, project: incident_project, author: guest) }
    let_it_be(:planner_incident) { create(:incident, project: incident_project, author: planner) }

    let(:issue) { incident }

    before_all do
      incident_project.add_guest(guest)
      incident_project.add_planner(planner)
      incident_project.add_reporter(reporter)
    end

    # Guests and planners can't manage metric images, even as the incident author.
    %i[guest planner].each do |role|
      context "as a #{role}" do
        let(:user) { public_send(role) }

        it { expect_allowed(:read_issuable_metric_image) }

        it 'does not allow managing metric images' do
          expect_disallowed(:upload_issuable_metric_image, :update_issuable_metric_image, :delete_issuable_metric_image)
        end

        context "on an incident the #{role} authored" do
          let(:issue) { public_send(:"#{role}_incident") }

          it 'does not allow managing metric images' do
            expect_disallowed(
              :upload_issuable_metric_image, :update_issuable_metric_image, :delete_issuable_metric_image
            )
          end
        end
      end
    end

    context 'as a reporter' do
      let(:user) { reporter }

      it 'allows managing metric images' do
        expect_allowed(
          :read_issuable_metric_image, :upload_issuable_metric_image, :update_issuable_metric_image,
          :delete_issuable_metric_image
        )
      end
    end
  end

  context 'when work item type is epic' do
    let_it_be(:author, freeze: false) { create(:user) }
    let_it_be(:assignee, freeze: false) { create(:user) }
    let_it_be(:project, freeze: false) { create(:project, :private, group: group) }
    let_it_be(:project_epic, freeze: false) { create(:issue, :epic, project: project) }

    context 'when epics feature is available' do
      before do
        stub_licensed_features(epics: true)
      end

      context 'as a guest' do
        let(:user) { guest }
        let(:issue) { project_epic }

        it { expect_allowed(:read_issue) }
      end

      context 'when project_work_item_epics feature flag is disabled' do
        before do
          stub_feature_flags(project_work_item_epics: false)
        end

        it_behaves_like 'prevents access to project-level {issues|work_items} with type Epic', :issue
      end
    end

    context 'when epics feature is not available' do
      before do
        stub_licensed_features(epics: false)
      end

      it_behaves_like 'prevents access to project-level {issues|work_items} with type Epic', :issue
    end
  end

  context 'when work item type is requirement' do
    let_it_be_with_refind(:project) { create(:project, :private, group: group) }
    let_it_be_with_refind(:requirement) { create(:work_item, :requirement, project: project) }

    let(:user) { reporter }
    let(:issue) { requirement }

    before do
      stub_licensed_features(requirements: true)
    end

    it { expect_allowed(:read_issue, :update_issue) }

    context 'when the requirements project feature is disabled' do
      before do
        project.project_feature.update!(requirements_access_level: ::ProjectFeature::DISABLED)
      end

      it { expect_disallowed(:read_issue, :update_issue, :admin_issue, :destroy_issue) }

      context 'as a guest reading through the generic issues surface' do
        let(:user) { guest }

        before_all do
          project.add_guest(guest)
        end

        it { expect_disallowed(:read_issue) }
      end

      context 'on a regular issue in the same project' do
        let(:issue) { build(:issue, project: project) }

        it { expect_allowed(:read_issue) }
      end
    end

    context 'when the requirements license is unavailable' do
      before do
        stub_licensed_features(requirements: false)
      end

      it { expect_disallowed(:read_issue, :update_issue, :admin_issue, :destroy_issue) }
    end
  end

  describe 'read_issuable_metric_image' do
    let_it_be(:public_project) { create(:project, :public) }
    let_it_be(:issues_private_project) { create(:project, :public, :issues_private) }
    let_it_be(:public_incident) { create(:incident, project: public_project) }
    let_it_be(:confidential_incident) { create(:incident, :confidential, project: public_project) }
    let_it_be(:members_only_incident) { create(:incident, project: issues_private_project) }
    let_it_be(:hidden_incident) { create(:incident, project: public_project, author: create(:user, :banned)) }
    let_it_be(:authored_confidential_incident) do
      create(:incident, :confidential, project: public_project, author: non_member)
    end

    before_all do
      public_project.add_guest(guest)
      public_project.add_planner(planner)
      issues_private_project.add_planner(planner)
    end

    where(:user, :issue, :allowed) do
      nil              | ref(:public_incident)                | true
      ref(:non_member) | ref(:public_incident)                | true
      nil              | ref(:confidential_incident)          | false
      ref(:non_member) | ref(:confidential_incident)          | false
      ref(:guest)      | ref(:confidential_incident)          | false
      ref(:planner)    | ref(:confidential_incident)          | true
      ref(:non_member) | ref(:authored_confidential_incident) | true
      nil              | ref(:members_only_incident)          | false
      ref(:non_member) | ref(:members_only_incident)          | false
      ref(:planner)    | ref(:members_only_incident)          | true
      nil              | ref(:hidden_incident)                | false
      ref(:non_member) | ref(:hidden_incident)                | false
      ref(:planner)    | ref(:hidden_incident)                | false
    end

    with_them do
      it { allowed ? expect_allowed(:read_issuable_metric_image) : expect_disallowed(:read_issuable_metric_image) }
    end

    context 'when the incident is hidden' do
      let(:user) { admin }
      let(:issue) { hidden_incident }

      context 'with admin mode enabled', :enable_admin_mode do
        it { expect_allowed(:read_issuable_metric_image) }
      end

      context 'without admin mode enabled' do
        it { expect_disallowed(:read_issuable_metric_image) }
      end
    end

    context 'in a private project' do
      let_it_be(:private_project) { create(:project, :private) }
      let_it_be(:private_incident) { create(:incident, project: private_project) }

      let(:issue) { private_incident }

      before_all do
        add_members(private_project)
      end

      where(:user, :allowed) do
        ref(:non_member) | false
        ref(:guest)      | true
        ref(:owner)      | true
      end

      with_them do
        it { allowed ? expect_allowed(:read_issuable_metric_image) : expect_disallowed(:read_issuable_metric_image) }
      end

      context 'with admin mode enabled', :enable_admin_mode do
        let(:user) { admin }

        it { expect_allowed(:read_issuable_metric_image) }
      end

      context 'without admin mode enabled' do
        let(:user) { admin }

        it { expect_disallowed(:read_issuable_metric_image) }
      end

      context 'as an auditor' do
        let(:user) { create(:user, :auditor) }

        it { expect_allowed(:read_issuable_metric_image) }
      end

      context 'when the issue is not an incident' do
        let_it_be(:private_issue) { create(:issue, project: private_project) }

        let(:user) { reporter }
        let(:issue) { private_issue }

        it { expect_disallowed(:read_issuable_metric_image) }
      end
    end
  end

  shared_examples 'metric image write permissions' do |permissions|
    let_it_be(:private_project) { create(:project, :private) }
    let_it_be(:private_incident) { create(:incident, project: private_project) }

    let(:issue) { private_incident }

    before_all do
      add_members(private_project)
    end

    where(:user, :allowed) do
      ref(:non_member) | false
      ref(:planner)    | false
      ref(:reporter)   | true
      ref(:owner)      | true
    end

    with_them do
      it { allowed ? expect_allowed(*permissions) : expect_disallowed(*permissions) }
    end

    context 'as an auditor' do
      let(:user) { create(:user, :auditor) }

      it { expect_disallowed(*permissions) }
    end

    # Admins who are not members are denied by the ~is_container_member prevent.
    context 'with admin mode enabled', :enable_admin_mode do
      let(:user) { admin }

      it { expect_disallowed(*permissions) }
    end

    context 'when a guest or planner authored the incident' do
      let_it_be(:guest_incident) { create(:incident, project: private_project, author: guest) }
      let_it_be(:planner_incident) { create(:incident, project: private_project, author: planner) }

      where(:user, :issue) do
        ref(:guest)   | ref(:guest_incident)
        ref(:planner) | ref(:planner_incident)
      end

      with_them do
        it { expect_disallowed(*permissions) }
      end
    end

    context 'as a reporter' do
      let(:user) { reporter }

      context 'when the incident is confidential' do
        let_it_be(:confidential_incident) { create(:incident, :confidential, project: private_project) }
        let(:issue) { confidential_incident }

        it { expect_allowed(*permissions) }
      end

      context 'when the incident is hidden' do
        let_it_be(:hidden_incident) { create(:incident, project: private_project, author: create(:user, :banned)) }
        let(:issue) { hidden_incident }

        it { expect_disallowed(*permissions) }
      end

      context 'when the issue is not an incident' do
        let_it_be(:private_issue) { create(:issue, project: private_project, author: reporter) }
        let(:issue) { private_issue }

        it { expect_disallowed(*permissions) }
      end

      context 'when the project is archived' do
        let_it_be(:archived_project) { create(:project, :private, :archived) }
        let_it_be(:archived_incident) { create(:incident, project: archived_project) }
        let(:issue) { archived_incident }

        before_all do
          archived_project.add_reporter(reporter)
        end

        it { expect_disallowed(*permissions) }
      end

      context 'when issues are disabled for the project' do
        let_it_be(:issues_disabled_project) { create(:project, :private, :issues_disabled) }
        let_it_be(:issues_disabled_incident) { create(:incident, project: issues_disabled_project) }
        let(:issue) { issues_disabled_incident }

        before_all do
          issues_disabled_project.add_reporter(reporter)
        end

        it { expect_disallowed(*permissions) }
      end
    end
  end

  describe 'upload, update and delete_issuable_metric_image' do
    it_behaves_like 'metric image write permissions',
      %i[upload_issuable_metric_image update_issuable_metric_image delete_issuable_metric_image]
  end
end
