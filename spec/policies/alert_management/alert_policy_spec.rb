# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AlertManagement::AlertPolicy, :models do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:alert) { create(:alert_management_alert, project: project, issue: incident) }
  let_it_be(:incident) { nil }

  subject(:policy) { described_class.new(user, alert) }

  it { is_expected.to delegate_to(ProjectPolicy) }

  describe 'rules' do
    shared_examples 'does not allow metric image reads' do
      it { expect_disallowed(:read_alert_management_metric_image) }
    end

    shared_examples 'does not allow metric image updates' do
      it { expect_disallowed(:upload_alert_management_metric_image, :destroy_alert_management_metric_image) }
    end

    shared_examples 'allows metric image reads' do
      it { expect_allowed(:read_alert_management_metric_image) }
    end

    shared_examples 'allows metric image updates' do
      it { expect_allowed(:upload_alert_management_metric_image, :destroy_alert_management_metric_image) }
    end

    context 'when user is not a member' do
      include_examples 'does not allow metric image reads'
      include_examples 'does not allow metric image updates'
    end

    context 'when user is a guest' do
      before_all do
        project.add_guest(user)
      end

      include_examples 'does not allow metric image reads'
      include_examples 'does not allow metric image updates'
    end

    context 'when user is a developer' do
      before_all do
        project.add_developer(user)
      end

      include_examples 'allows metric image reads'
      include_examples 'allows metric image updates'
    end
  end
end
