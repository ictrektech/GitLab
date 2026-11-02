# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/FactoryBot/AvoidCreate -- enrollment checks require DB persistence
RSpec.describe SecretsManagement::Availability, feature_category: :secrets_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :empty_repo, group: group) }

  describe '.for_project?' do
    before do
      stub_licensed_features(native_secrets_management: true)
    end

    context 'when namespace is enrolled', :saas do
      before_all do
        create(:secrets_manager_namespace_enrollment, namespace: group)
      end

      it 'returns true' do
        expect(described_class.for_project?(project)).to be true
      end
    end

    context 'when instance is enrolled' do
      before do
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns true' do
        expect(described_class.for_project?(project)).to be true
      end
    end

    context 'when not enrolled' do
      it 'returns false' do
        expect(described_class.for_project?(project)).to be false
      end
    end

    context 'when license is not available' do
      before do
        stub_licensed_features(native_secrets_management: false)
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns false' do
        expect(described_class.for_project?(project)).to be false
      end
    end
  end

  describe '.for_group?' do
    before do
      stub_licensed_features(native_secrets_management: true)
    end

    context 'when namespace is enrolled', :saas do
      before_all do
        create(:secrets_manager_namespace_enrollment, namespace: group)
      end

      it 'returns true' do
        expect(described_class.for_group?(group)).to be true
      end
    end

    context 'when instance is enrolled' do
      before do
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns true' do
        expect(described_class.for_group?(group)).to be true
      end
    end

    context 'when not enrolled' do
      it 'returns false' do
        expect(described_class.for_group?(group)).to be false
      end
    end

    context 'when group is a top-level group on SaaS', :saas do
      let_it_be(:subgroup) { create(:group, parent: group) }

      it 'returns true for the top-level group even when not enrolled' do
        expect(described_class.for_group?(group)).to be true
      end

      it 'returns false for a subgroup when the root is not enrolled' do
        expect(described_class.for_group?(subgroup)).to be false
      end

      context 'when the root is enrolled' do
        before_all do
          create(:secrets_manager_namespace_enrollment, namespace: group)
        end

        it 'returns true for a subgroup' do
          expect(described_class.for_group?(subgroup)).to be true
        end
      end

      context 'when the root explicitly opted out' do
        before_all do
          create(:secrets_manager_namespace_enrollment, :disabled, namespace: group)
        end

        it 'returns false for the top-level group' do
          expect(described_class.for_group?(group)).to be false
        end

        it 'returns false for a subgroup' do
          expect(described_class.for_group?(subgroup)).to be false
        end
      end
    end

    context 'when license is not available' do
      before do
        stub_licensed_features(native_secrets_management: false)
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns false' do
        expect(described_class.for_group?(group)).to be false
      end
    end
  end

  describe '.licensed?' do
    context 'when the group explicitly opted out', :saas do
      before_all do
        create(:secrets_manager_namespace_enrollment, :disabled, namespace: group)
      end

      before do
        stub_licensed_features(native_secrets_management: true)
      end

      it 'stays true, unlike for_group?' do
        expect(described_class.licensed?(group)).to be true
        expect(described_class.for_group?(group)).to be false
      end
    end

    context 'when the license is not available' do
      before do
        stub_licensed_features(native_secrets_management: false)
      end

      it 'returns false' do
        expect(described_class.licensed?(group)).to be false
      end
    end
  end

  describe '.for_instance?' do
    context 'when license is available and instance is enrolled' do
      before do
        allow(::License).to receive(:feature_available?).and_call_original
        allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(true)
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns true' do
        expect(described_class.for_instance?).to be true
      end
    end

    context 'when license is not available' do
      before do
        allow(::License).to receive(:feature_available?).and_call_original
        allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(false)
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns false' do
        expect(described_class.for_instance?).to be false
      end
    end

    context 'when instance is not enrolled' do
      before do
        allow(::License).to receive(:feature_available?).and_call_original
        allow(::License).to receive(:feature_available?).with(:native_secrets_management).and_return(true)
      end

      it 'returns false' do
        expect(described_class.for_instance?).to be false
      end
    end
  end

  describe '.namespace_configurable?' do
    using RSpec::Parameterized::TableSyntax

    let_it_be_with_refind(:root_group) { create(:group) }
    let_it_be_with_refind(:nested_group) { create(:group, :nested) }

    subject(:available) { described_class.namespace_configurable?(group) }

    # `enrollable` is the SaaS arm (NamespaceEnrollment.enrollment_allowed? is
    # SaaS-only); `sm_status` is the local provisioning record, nil when the
    # group has never provisioned.
    where(:case_name, :group, :enrollable, :sm_available, :sm_status, :expected) do
      'provisioned subgroup'                 | ref(:nested_group) | false | true  | :active       | false
      'unprovisioned subgroup'               | ref(:nested_group) | false | true  | nil           | false
      'enrollable (SaaS), unprovisioned'     | ref(:root_group)   | true  | true  | nil           | true
      'enrollable (SaaS), not yet available' | ref(:root_group)   | true  | false | nil           | true
      'unavailable and not enrollable'       | ref(:root_group)   | false | false | nil           | false
      'not enrollable, unprovisioned'        | ref(:root_group)   | false | true  | nil           | false
      'not enrollable, provisioning'         | ref(:root_group)   | false | true  | :provisioning | false
      'not enrollable, provisioned'          | ref(:root_group)   | false | true  | :active       | true
    end

    with_them do
      before do
        allow(SecretsManagement::NamespaceEnrollment)
          .to receive(:enrollment_allowed?).with(group).and_return(enrollable)
        allow(described_class).to receive(:for_group?).with(group).and_return(sm_available)

        create(:group_secrets_manager, sm_status, group: group) if sm_status
      end

      it { is_expected.to be(expected) }
    end
  end

  describe '.enabled_for_project?' do
    context 'when namespace is enrolled', :saas do
      before_all do
        create(:secrets_manager_namespace_enrollment, namespace: group)
      end

      it 'returns true' do
        expect(described_class.enabled_for_project?(project)).to be true
      end
    end

    context 'when instance is enrolled' do
      before do
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns true' do
        expect(described_class.enabled_for_project?(project)).to be true
      end
    end

    context 'when not enrolled' do
      it 'returns false' do
        expect(described_class.enabled_for_project?(project)).to be false
      end
    end

    it 'does not require the license' do
      stub_licensed_features(native_secrets_management: false)
      stub_application_setting(secrets_manager_instance_enrolled: true)

      expect(described_class.enabled_for_project?(project)).to be true
    end
  end

  describe '.enabled_for_group?' do
    context 'when namespace is enrolled', :saas do
      before_all do
        create(:secrets_manager_namespace_enrollment, namespace: group)
      end

      it 'returns true' do
        expect(described_class.enabled_for_group?(group)).to be true
      end
    end

    context 'when instance is enrolled' do
      before do
        stub_application_setting(secrets_manager_instance_enrolled: true)
      end

      it 'returns true' do
        expect(described_class.enabled_for_group?(group)).to be true
      end
    end

    context 'when not enrolled' do
      it 'returns false' do
        expect(described_class.enabled_for_group?(group)).to be false
      end
    end

    context 'when group is a top-level group on SaaS', :saas do
      let_it_be(:subgroup) { create(:group, parent: group) }

      it 'returns true for the top-level group even when not enrolled' do
        expect(described_class.enabled_for_group?(group)).to be true
      end

      it 'returns false for a subgroup when the root is not enrolled' do
        expect(described_class.enabled_for_group?(subgroup)).to be false
      end

      context 'when the root explicitly opted out' do
        before_all do
          create(:secrets_manager_namespace_enrollment, :disabled, namespace: group)
        end

        it 'returns false for the top-level group' do
          expect(described_class.enabled_for_group?(group)).to be false
        end

        it 'returns false for a subgroup' do
          expect(described_class.enabled_for_group?(subgroup)).to be false
        end
      end
    end

    context 'when the group is a top-level group on self-managed' do
      before do
        stub_application_setting(secrets_manager_instance_enrolled: false)
      end

      it 'does not grant access when the instance is not enrolled' do
        expect(described_class.enabled_for_group?(group)).to be false
      end

      context 'when the instance is enrolled' do
        before do
          stub_application_setting(secrets_manager_instance_enrolled: true)
        end

        it 'returns true via instance enrollment' do
          expect(described_class.enabled_for_group?(group)).to be true
        end
      end
    end

    it 'does not require the license' do
      stub_licensed_features(native_secrets_management: false)
      stub_application_setting(secrets_manager_instance_enrolled: true)

      expect(described_class.enabled_for_group?(group)).to be true
    end
  end
end
# rubocop:enable RSpec/FactoryBot/AvoidCreate
