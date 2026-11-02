# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecretsHelper, feature_category: :secrets_management do
  let_it_be(:group) { create(:group) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- need persisted object
  let_it_be(:sub_group) { create(:group, parent: group) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- need persisted object
  let_it_be(:project) { create(:project, group: group) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- need persisted object
  let_it_be(:owner) { create(:user) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- need persisted object
  let_it_be(:maintainer) { create(:user) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- need persisted object

  describe '#project_secrets_app_data' do
    subject(:data) { helper.project_secrets_app_data(project) }

    before do
      allow(helper).to receive(:current_user).and_return(maintainer)
      stub_secrets_manager_entitlement
    end

    it 'returns expected data' do
      expect(data).to include({
        project_path: project.full_path,
        base_path: project_secrets_path(project)
      })
    end

    it 'returns secrets manager permissions settings path' do
      expect(data[:manage_permissions_path]).to eq(
        edit_project_path(project, anchor: 'js-shared-permissions')
      )
    end

    it 'returns whether the instance license is offline' do
      allow(::SecretsManagement::InstanceEnrollment).to receive(:offline_license?).and_return(true)

      expect(data[:is_offline_license]).to eq('true')
    end

    describe 'can_start_trial' do
      before_all do
        group.add_owner(owner)
        group.add_maintainer(maintainer)
      end

      context 'when the current user is an Owner of the top-level group', :saas do
        before do
          stub_licensed_features(native_secrets_management: true)
          allow(helper).to receive(:current_user).and_return(owner)
        end

        it { expect(data[:can_start_trial]).to eq('true') }

        # Same ability as the mutation: on self-managed the trial is instance-wide.
        context 'when not on GitLab.com' do
          before do
            stub_saas_features(gitlab_com_subscriptions: false)
          end

          it { expect(data[:can_start_trial]).to eq('false') }
        end
      end

      context 'when the current user is not an Owner of the top-level group', :saas do
        before do
          stub_licensed_features(native_secrets_management: true)
        end

        it { expect(data[:can_start_trial]).to eq('false') }
      end
    end

    describe 'can_enable_add_on' do
      before_all do
        group.add_owner(owner)
        group.add_maintainer(maintainer)
      end

      before do
        stub_licensed_features(native_secrets_management: true)
      end

      context 'when the current user is an Owner of the top-level group', :saas do
        before do
          allow(helper).to receive(:current_user).and_return(owner)
        end

        it { expect(data[:can_enable_add_on]).to eq('true') }

        # Same ability as the mutation: on self-managed the add-on is instance-wide.
        context 'when not on GitLab.com' do
          before do
            stub_saas_features(gitlab_com_subscriptions: false)
          end

          it { expect(data[:can_enable_add_on]).to eq('false') }
        end
      end

      context 'when the current user is not an Owner of the top-level group', :saas do
        it { expect(data[:can_enable_add_on]).to eq('false') }
      end
    end

    describe 'can_provision' do
      let_it_be(:developer) { create(:user, developer_of: group) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- need persisted object
      let_it_be(:reporter) { create(:user, reporter_of: group) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- need persisted object

      before_all do
        group.add_owner(owner)
        group.add_maintainer(maintainer)
      end

      before do
        stub_licensed_features(native_secrets_management: true)
        allow(::SecretsManagement::Availability).to receive(:enabled_for_project?).with(project).and_return(true)
        stub_secrets_manager_entitlement(state: :paid)
      end

      context 'when the current user is a project Owner' do
        before do
          allow(helper).to receive(:current_user).and_return(owner)
        end

        it { expect(data[:can_provision]).to eq('true') }
      end

      context 'when the current user is a Maintainer' do
        it { expect(data[:can_provision]).to eq('true') }
      end

      context 'when the current user is a Developer' do
        before do
          allow(helper).to receive(:current_user).and_return(developer)
        end

        it { expect(data[:can_provision]).to eq('true') }
      end

      context 'when the current user is a Reporter' do
        before do
          allow(helper).to receive(:current_user).and_return(reporter)
        end

        it { expect(data[:can_provision]).to eq('false') }
      end
    end

    context 'when on SaaS', :saas do
      it 'includes enrollment_settings_path pointing to the root group Secure settings' do
        expect(data[:enrollment_settings_path]).to eq(
          group_settings_secure_path(project.root_ancestor, anchor: 'js-secrets-manager-settings')
        )
      end
    end

    context 'when on self-managed with instance enrollment allowed' do
      before do
        allow(helper).to receive(:allow_secrets_manager_instance_enrollment?).and_return(true)
      end

      it 'includes enrollment_settings_path pointing to admin settings' do
        expect(data[:enrollment_settings_path]).to eq(
          general_admin_application_settings_path(anchor: 'js-secrets-manager-instance-enrollment-settings')
        )
      end
    end

    context 'when project belongs to a group' do
      it 'returns the top-level group full path' do
        expect(data[:top_level_group_full_path]).to eq(group.full_path)
      end
    end

    context 'when project belongs to a personal namespace', :saas do
      let_it_be(:namespace_owner) { create(:user, :with_namespace) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- need persisted object
      let_it_be(:user_project) { create(:project, namespace: namespace_owner.namespace) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- need persisted object

      subject(:personal_data) { helper.project_secrets_app_data(user_project) }

      before do
        stub_licensed_features(native_secrets_management: true)
        allow(helper).to receive(:current_user).and_return(namespace_owner)
      end

      it 'returns an empty string for top_level_group_full_path' do
        expect(personal_data[:top_level_group_full_path]).to eq('')
      end

      # Personal namespaces have no trial or add-on, even for the namespace owner.
      it 'returns false for the billing flags' do
        expect(personal_data).to include(can_start_trial: 'false', can_enable_add_on: 'false')
      end

      # can_provision follows whatever entitlement resolves for the project
      # (root_namespace.root_ancestor_for is nil here, so `Entitlement.for`
      # resolves it: ineligible on SaaS, the instance entitlement on
      # self-managed, per ee/lib/secrets_management/entitlement/resolver.rb).
      # That SaaS-resolves-to-ineligible behavior for a nil namespace is asserted
      # at the policy layer (ProjectPolicy spec, "when on GitLab.com without a
      # stubbed entitlement"); here we only need to prove the helper passes the
      # entitlement's answer through, in whichever state it comes back as.
      #
      # Provisioning a *new* personal-namespace project is a separate question
      # this ability does not answer: `ProjectSecretsManagers::InitializeService`
      # refuses any project in a user namespace regardless of what this boolean
      # says, so a self-managed instance in a write state can still show a
      # provision CTA that fails on click for a never-provisioned personal project.
      context 'when the resolved entitlement permits writes' do
        before do
          allow(::SecretsManagement::Availability).to receive(:enabled_for_project?).with(user_project)
            .and_return(true)
          stub_secrets_manager_entitlement(state: :paid)
        end

        it 'returns true for can_provision' do
          expect(personal_data).to include(can_provision: 'true')
        end
      end

      context 'when the resolved entitlement blocks writes' do
        before do
          allow(::SecretsManagement::Availability).to receive(:enabled_for_project?).with(user_project)
            .and_return(true)
          stub_secrets_manager_entitlement(state: :blocked, blocked_reason: :trial_expired)
        end

        it 'returns false for can_provision' do
          expect(personal_data).to include(can_provision: 'false')
        end
      end
    end
  end

  describe '#group_secrets_app_data' do
    subject(:data) { helper.group_secrets_app_data(group) }

    before do
      allow(helper).to receive(:current_user).and_return(maintainer)
      stub_secrets_manager_entitlement
    end

    it 'returns expected data' do
      expect(data).to include({
        group_path: group.full_path,
        base_path: group_secrets_path(group),
        top_level_group_full_path: group.full_path
      })
    end

    it 'returns secrets manager permissions settings path pointing to the Secure settings' do
      expect(data[:manage_permissions_path]).to eq(
        group_settings_secure_path(group, anchor: 'js-secrets-manager-settings')
      )
    end

    describe 'can_start_trial' do
      before_all do
        group.add_owner(owner)
        group.add_maintainer(maintainer)
      end

      context 'when the current user is an Owner of the top-level group', :saas do
        before do
          stub_licensed_features(native_secrets_management: true)
          allow(helper).to receive(:current_user).and_return(owner)
        end

        it { expect(data[:can_start_trial]).to eq('true') }

        # Same ability as the mutation: on self-managed the trial is instance-wide.
        context 'when not on GitLab.com' do
          before do
            stub_saas_features(gitlab_com_subscriptions: false)
          end

          it { expect(data[:can_start_trial]).to eq('false') }
        end
      end

      context 'when the current user is not an Owner of the top-level group', :saas do
        before do
          stub_licensed_features(native_secrets_management: true)
        end

        it { expect(data[:can_start_trial]).to eq('false') }
      end

      context 'when viewing a sub-group' do
        subject(:sub_group_data) { helper.group_secrets_app_data(sub_group) }

        # Ownership is inherited from the root; the flag is scoped to the top-level group.
        context 'and the current user is an Owner of the root group', :saas do
          before do
            stub_licensed_features(native_secrets_management: true)
            allow(helper).to receive(:current_user).and_return(owner)
          end

          it { expect(sub_group_data[:can_start_trial]).to eq('true') }
        end
      end
    end

    describe 'can_enable_add_on' do
      before_all do
        group.add_owner(owner)
        group.add_maintainer(maintainer)
      end

      before do
        stub_licensed_features(native_secrets_management: true)
      end

      context 'when the current user is an Owner of the top-level group', :saas do
        before do
          allow(helper).to receive(:current_user).and_return(owner)
        end

        it { expect(data[:can_enable_add_on]).to eq('true') }

        context 'when not on GitLab.com' do
          before do
            stub_saas_features(gitlab_com_subscriptions: false)
          end

          it { expect(data[:can_enable_add_on]).to eq('false') }
        end

        # The flag is scoped to the top-level group, like can_start_trial.
        context 'when viewing a sub-group' do
          subject(:sub_group_data) { helper.group_secrets_app_data(sub_group) }

          it { expect(sub_group_data[:can_enable_add_on]).to eq('true') }
        end
      end

      context 'when the current user is not an Owner of the top-level group', :saas do
        it { expect(data[:can_enable_add_on]).to eq('false') }
      end
    end

    describe 'can_provision' do
      before_all do
        group.add_owner(owner)
        group.add_maintainer(maintainer)
      end

      before do
        stub_licensed_features(native_secrets_management: true)
        allow(::SecretsManagement::Availability).to receive(:enabled_for_group?).and_return(true)
        stub_secrets_manager_entitlement(state: :paid)
      end

      context 'when the current user is a group Owner' do
        before do
          allow(helper).to receive(:current_user).and_return(owner)
        end

        it { expect(data[:can_provision]).to eq('true') }

        # Unlike the billing flags, provisioning is decided on the group being viewed.
        context 'when viewing a sub-group' do
          subject(:sub_group_data) { helper.group_secrets_app_data(sub_group) }

          it { expect(sub_group_data[:can_provision]).to eq('true') }
        end
      end

      context 'when the current user is a Maintainer' do
        it { expect(data[:can_provision]).to eq('false') }
      end
    end

    context 'when group is already top-level' do
      subject(:group_data) { helper.group_secrets_app_data(group) }

      it 'returns the group full path' do
        expect(group_data[:top_level_group_full_path]).to eq(group.full_path)
      end
    end

    context 'when group is a sub-group' do
      subject(:sub_group_data) { helper.group_secrets_app_data(sub_group) }

      it 'returns the top-level group full path' do
        expect(sub_group_data[:top_level_group_full_path]).to eq(group.full_path)
      end

      it 'returns the manage_permissions_path pointing to General settings' do
        expect(sub_group_data[:manage_permissions_path]).to eq(
          edit_group_path(sub_group, anchor: 'js-permissions-settings')
        )
      end
    end

    context 'when on SaaS', :saas do
      it 'includes enrollment_settings_path pointing to the root group Secure settings' do
        expect(data[:enrollment_settings_path]).to eq(
          group_settings_secure_path(group, anchor: 'js-secrets-manager-settings')
        )
      end

      context 'when group is a sub-group' do
        subject(:sub_group_data) { helper.group_secrets_app_data(sub_group) }

        # Enrollment always targets the root ancestor, whose settings now live under Secure.
        it 'includes enrollment_settings_path pointing to the root group Secure settings' do
          expect(sub_group_data[:enrollment_settings_path]).to eq(
            group_settings_secure_path(group, anchor: 'js-secrets-manager-settings')
          )
        end
      end
    end

    context 'when on self-managed with instance enrollment allowed' do
      before do
        allow(helper).to receive(:allow_secrets_manager_instance_enrollment?).and_return(true)
      end

      it 'includes enrollment_settings_path pointing to admin application settings' do
        expect(data[:enrollment_settings_path]).to eq(
          general_admin_application_settings_path(anchor: 'js-secrets-manager-instance-enrollment-settings')
        )
      end
    end
  end

  describe '#namespace_enrollment_data' do
    before_all do
      group.add_owner(owner)
      group.add_maintainer(maintainer)
    end

    subject(:group_enrollment) { helper.namespace_enrollment_data(group, owner) }

    it 'returns expected data' do
      expect(group_enrollment).to include({
        full_path: group.full_path,
        is_namespace_enrollable: 'false',
        top_level_group_full_path: group.full_path
      })
    end

    context 'when user is a maintainer of the group', :saas do
      subject(:group_enrollment_with_maintainer) { helper.namespace_enrollment_data(group, maintainer) }

      it 'sets correct permissions' do
        expect(group_enrollment_with_maintainer).to include({
          can_manage_secrets_manager: 'false',
          can_enroll_namespace: 'false',
          can_start_trial: 'false'
        })
      end
    end

    context 'when user is the owner of the top-level group', :saas do
      before do
        stub_licensed_features(native_secrets_management: true)
      end

      it { expect(group_enrollment).to include(can_start_trial: 'true') }
    end

    context 'when user is the owner' do
      using RSpec::Parameterized::TableSyntax

      # only enrollable when SaaS + top-level group
      where(:is_saas, :namespace, :expected_enrollable) do
        true  | ref(:group)     | 'true'
        true  | ref(:sub_group) | 'false'
        false | ref(:group)     | 'false'
        false | ref(:sub_group) | 'false'
      end

      with_them do
        before do
          allow(Gitlab).to receive(:com?).and_return(is_saas) # -- testing Gitlab.com? behavior directly
        end

        subject(:group_enrollment_with_owner) { helper.namespace_enrollment_data(namespace, owner) }

        it 'returns correct is_namespace_enrollable' do
          expect(group_enrollment_with_owner).to include(is_namespace_enrollable: expected_enrollable)
        end

        it 'returns top_level_group_full_path pointing to root ancestor' do
          expect(group_enrollment_with_owner).to include(
            top_level_group_full_path: group.full_path
          )
        end
      end
    end
  end

  describe '#secrets_manager_vulnerability_cta_data' do
    subject(:cta_data) { helper.secrets_manager_vulnerability_cta_data(project, 'secret_detection') }

    let_it_be(:personal_project) { create(:project) } # rubocop:disable RSpec/FactoryBot/AvoidCreate -- need persisted object

    before do
      stub_feature_flags(secrets_manager_vulnerability_cta: true)
      allow(helper).to receive_messages(current_user: maintainer, can?: false)
      # The secrets manager is licensed for the group; the user's abilities
      # and the enrollment state vary per context below.
      allow(SecretsManagement::Availability).to receive_messages(licensed?: true, for_group?: true)
    end

    context 'when the report_type is not secret_detection' do
      subject(:cta_data) { helper.secrets_manager_vulnerability_cta_data(project, 'sast') }

      it { is_expected.to eq({}) }
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(secrets_manager_vulnerability_cta: false)
      end

      it { is_expected.to eq({}) }
    end

    it 'links to the project Secrets Manager page' do
      expect(cta_data[:secrets_path]).to eq(project_secrets_path(project))
    end

    it 'reports every ability as false when the user has none' do
      expect(cta_data).to include(secrets_manager_available: false, can_start_trial: false)
    end

    context 'when the secrets manager is not licensed for the group' do
      before do
        allow(SecretsManagement::Availability).to receive_messages(licensed?: false, for_group?: false)
      end

      it 'returns an empty payload so the card is hidden' do
        expect(cta_data).to eq({})
      end
    end

    context 'when the group is licensed but not enrolled' do
      before do
        allow(SecretsManagement::Availability).to receive_messages(licensed?: true, for_group?: false)
      end

      it 'still shows the card, so a non-actor can request access from an owner' do
        expect(cta_data).to include(secrets_manager_available: false, can_start_trial: false)
        expect(cta_data[:secrets_path]).to be_present
      end
    end

    context 'when the user can read project secrets' do
      before do
        allow(helper).to receive(:can?).with(maintainer, :read_project_secrets, project).and_return(true)
      end

      it 'reports the view variant without requiring the project to be provisioned' do
        expect(project.secrets_manager).to be_nil
        expect(cta_data).to include(secrets_manager_available: true)
      end

      it 'does not resolve the billing entitlement' do
        expect(SecretsManagement::Entitlement).not_to receive(:for)

        cta_data
      end
    end

    context 'when the project is enrolled but the policy denies reading secrets' do
      before do
        # Enrolled group with a trial-eligible entitlement: availability is
        # true, but the secrets page itself 404s (read_project_secrets is
        # prevented until the entitlement moves past trial-eligible).
        allow(helper).to receive(:can?).with(maintainer, :read_project_secrets, project).and_return(false)
      end

      it 'does not report available, so the view CTA cannot link to a page that 404s' do
        expect(cta_data).to include(secrets_manager_available: false)
      end
    end

    context 'when the root namespace is not a group' do
      subject(:cta_data) { helper.secrets_manager_vulnerability_cta_data(personal_project, 'secret_detection') }

      it 'hides the card: a personal namespace can never enroll, so there is nothing to try or request' do
        expect(personal_project.root_ancestor).not_to be_a(Group)
        expect(cta_data).to eq({})
      end
    end

    context 'when the root namespace is a group' do
      before do
        allow(helper).to receive(:can?).with(maintainer, :start_secrets_manager_trial, group).and_return(true)
      end

      it 'offers the trial and points the start trial path at the top-level group Secrets Manager page' do
        expect(cta_data).to include(can_start_trial: true, start_trial_path: group_secrets_path(group))
      end

      context 'when the group has opted out of the secrets manager' do
        before do
          # An explicit opt-out revokes availability (the group secrets page
          # would 404) but the feature stays licensed, so Try goes to settings.
          allow(SecretsManagement::Availability).to receive(:for_group?).with(group).and_return(false)
          create(:secrets_manager_namespace_enrollment, :disabled, namespace: group) # rubocop:disable RSpec/FactoryBot/AvoidCreate -- opted_out? queries the table
        end

        it 'points the start trial path at the Secure settings, where re-enabling lives' do
          expect(cta_data).to include(
            can_start_trial: true,
            start_trial_path: group_settings_secure_path(group, anchor: 'js-secrets-manager-settings')
          )
        end

        context 'when the group is no longer licensed' do
          before do
            allow(SecretsManagement::Availability).to receive_messages(licensed?: false, for_group?: false)
          end

          it 'hides the card: an opt-out without a license is not offered anything' do
            expect(cta_data).to eq({})
          end
        end
      end
    end

    context 'when the user has the instance-level trial ability' do
      before do
        allow(helper).to receive(:can?).with(maintainer, :start_secrets_manager_trial).and_return(true)
      end

      it 'offers the trial and points the start trial path at the Admin area settings' do
        expect(cta_data).to include(
          can_start_trial: true,
          start_trial_path: general_admin_application_settings_path(
            anchor: 'js-secrets-manager-instance-enrollment-settings'
          )
        )
      end
    end
  end

  describe '#secrets_manager_variables_cta_data' do
    subject(:data) { helper.secrets_manager_variables_cta_data(entity) }

    let(:cta_group) { build_stubbed(:group) }
    let(:cta_subgroup) { build_stubbed(:group, parent: cta_group) }
    let(:cta_project) { build_stubbed(:project, namespace: cta_group) }
    let(:cta_personal_project) { build_stubbed(:project, namespace: build_stubbed(:user_namespace)) }
    let(:current_user) { build_stubbed(:user) }
    let(:entity) { cta_project }

    let(:can_start_instance_trial) { false }
    let(:can_start_group_trial) { false }
    let(:can_read_project_secrets) { false }
    let(:can_read_group_secrets) { false }
    let(:available_for_instance) { false }
    let(:available_for_group) { true }
    let(:licensed) { true }
    let(:opted_out) { false }
    let(:instance_settings_path) do
      general_admin_application_settings_path(anchor: 'js-secrets-manager-instance-enrollment-settings')
    end

    before do
      stub_feature_flags(secrets_manager_variables_cta: true)
      allow(helper).to receive_messages(current_user: current_user, can?: false)
      allow(helper).to receive(:can?).with(current_user, :start_secrets_manager_trial)
        .and_return(can_start_instance_trial)
      allow(helper).to receive(:can?).with(current_user, :start_secrets_manager_trial, cta_group)
        .and_return(can_start_group_trial)
      allow(helper).to receive(:can?).with(current_user, :read_project_secrets, anything)
        .and_return(can_read_project_secrets)
      allow(helper).to receive(:can?).with(current_user, :read_secret, anything).and_return(can_read_group_secrets)
      allow(cta_subgroup).to receive(:root_ancestor).and_return(cta_group)
      allow(SecretsManagement::Availability).to receive_messages(
        licensed?: licensed, for_instance?: available_for_instance, for_group?: available_for_group
      )
      allow(SecretsManagement::NamespaceEnrollment).to receive(:opted_out?).with(cta_group).and_return(opted_out)
    end

    context 'with no current user' do
      let(:current_user) { nil }

      it { is_expected.to eq({}) }
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(secrets_manager_variables_cta: false)
      end

      it { is_expected.to eq({}) }

      context 'with the instance' do
        let(:entity) { nil }

        it { is_expected.to eq({}) }
      end
    end

    context 'when the feature flag is enabled only for another group' do
      before do
        stub_feature_flags(secrets_manager_variables_cta: build_stubbed(:group))
      end

      it { is_expected.to eq({}) }
    end

    context 'when the feature flag is enabled only for the top-level group' do
      let(:can_read_project_secrets) { true }

      before do
        stub_feature_flags(secrets_manager_variables_cta: false)
        stub_feature_flags(secrets_manager_variables_cta: cta_group)
      end

      it { is_expected.to be_present }
    end

    context 'when only the vulnerability flag is enabled' do
      before do
        stub_feature_flags(secrets_manager_variables_cta: false, secrets_manager_vulnerability_cta: true)
      end

      it { is_expected.to eq({}) }
    end

    # The SaaS enrollment is per top-level group, so a project and a subgroup both resolve to it.
    context 'when the group has never enrolled' do
      context 'with a project and a user who can start a trial' do
        let(:can_start_group_trial) { true }

        it 'offers the trial on the top-level group secrets page' do
          expect(data).to eq(
            secrets_manager_available: false, can_start_trial: true,
            secrets_path: project_secrets_path(cta_project), start_trial_path: group_secrets_path(cta_group)
          )
        end

        it 'makes no CustomersDot lookup' do
          expect(SecretsManagement::Entitlement).not_to receive(:for)

          data
        end
      end

      # A top-level group that has not opted out counts as available, while its projects need an enrollment.
      context 'with the top-level group' do
        let(:entity) { cta_group }
        let(:can_read_group_secrets) { true }

        it 'can already read the group secrets, so the group page shows the view card' do
          expect(data).to include(secrets_manager_available: true, secrets_path: group_secrets_path(cta_group))
        end
      end

      context 'with a subgroup' do
        let(:entity) { cta_subgroup }
        let(:can_start_group_trial) { true }

        it 'is not available, and starts the trial on the top-level group' do
          expect(data).to include(
            secrets_manager_available: false, can_start_trial: true, start_trial_path: group_secrets_path(cta_group)
          )
        end
      end

      context 'with a user who cannot start a trial' do
        it 'still shows the card, so they can ask an owner for access' do
          expect(data).to eq(
            secrets_manager_available: false, can_start_trial: false, secrets_path: project_secrets_path(cta_project)
          )
        end
      end
    end

    context 'when the group has enrolled' do
      let(:can_read_project_secrets) { true }

      it 'is available for the project, which links to its secrets page' do
        expect(data).to include(secrets_manager_available: true, secrets_path: project_secrets_path(cta_project))
      end

      context 'with the top-level group' do
        let(:entity) { cta_group }
        let(:can_read_group_secrets) { true }

        it 'is available and links to the group secrets page' do
          expect(data).to include(secrets_manager_available: true, secrets_path: group_secrets_path(cta_group))
        end
      end
    end

    context 'when the group has opted out' do
      let(:available_for_group) { false }
      let(:opted_out) { true }
      let(:can_start_group_trial) { true }

      it 'is not available, and the trial goes to the Secure settings where re-enabling lives' do
        expect(data).to include(
          secrets_manager_available: false, can_start_trial: true,
          start_trial_path: group_settings_secure_path(cta_group, anchor: 'js-secrets-manager-settings')
        )
      end

      context 'with the top-level group' do
        let(:entity) { cta_group }

        it 'is not available either' do
          expect(data).to include(secrets_manager_available: false, can_start_trial: true)
        end
      end
    end

    # The license is enforced by `Availability` and the trial ability, not by a check in the helper.
    context 'when Secrets Manager is not licensed' do
      let(:licensed) { false }
      let(:available_for_group) { false }

      it { is_expected.to eq({}) }

      context 'with the top-level group' do
        let(:entity) { cta_group }

        it { is_expected.to eq({}) }
      end
    end

    context 'with a personal project' do
      let(:entity) { cta_personal_project }

      it 'shows nothing, because there is no top-level group to start a trial on or ask for access' do
        expect(data).to eq({})
      end

      context 'when the user can start an instance trial' do
        let(:can_start_instance_trial) { true }

        it 'offers the trial in the Admin area settings' do
          expect(data).to include(can_start_trial: true, start_trial_path: instance_settings_path)
        end
      end
    end

    context 'when the user can read project secrets and also start a trial' do
      let(:can_read_project_secrets) { true }
      let(:can_start_instance_trial) { true }

      # The component shows the view card whenever it is available and ignores the trial path.
      it 'sends both the secrets path and the trial path' do
        expect(data).to include(
          secrets_manager_available: true, secrets_path: project_secrets_path(cta_project),
          can_start_trial: true, start_trial_path: instance_settings_path
        )
      end
    end

    context 'with the instance (admin area)' do
      let(:entity) { nil }

      context 'when Secrets Manager is available' do
        let(:available_for_instance) { true }

        it 'has no secrets path, because there are no instance-level secrets' do
          expect(data).to eq(secrets_manager_available: true, can_start_trial: false)
        end
      end

      context 'when Secrets Manager is not available' do
        context 'when the user can start an instance trial' do
          let(:can_start_instance_trial) { true }

          it 'offers the trial in the Admin area settings' do
            expect(data).to eq(
              secrets_manager_available: false, can_start_trial: true, start_trial_path: instance_settings_path
            )
          end
        end

        # Nobody could act on the card, and there is no group to ask.
        context 'when the user cannot start a trial' do
          it { is_expected.to eq({}) }
        end
      end
    end
  end
end
