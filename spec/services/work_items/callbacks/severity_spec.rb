# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Callbacks::Severity, feature_category: :incident_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:reporter) { create(:user, reporter_of: project) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be_with_reload(:work_item) { create(:work_item, :incident, project: project) }

  let(:current_user) { reporter }
  let(:params) { { severity: 'critical' } }
  let(:callback) { described_class.new(issuable: work_item, current_user: current_user, params: params) }

  describe '#before_create' do
    let(:work_item) { build(:work_item, :incident, project: project) }

    subject(:create_with_severity) do
      callback.before_create
      work_item.save!
    end

    it 'sets the severity' do
      create_with_severity

      expect(work_item.reload.severity).to eq('critical')
    end

    context 'when user is a planner, who cannot admin incidents' do
      let_it_be(:planner) { create(:user, planner_of: project) }
      let(:current_user) { planner }

      it 'does not set the severity' do
        create_with_severity

        expect(work_item.reload.severity).to eq(IssuableSeverity::DEFAULT)
      end
    end
  end

  describe '#before_update' do
    subject(:update_severity) do
      callback.before_update
      work_item.save!
    end

    it 'updates the severity' do
      expect { update_severity }.to change { work_item.reload.severity }.from('unknown').to('critical')
    end

    context 'when severity param matches the current severity' do
      let(:params) { { severity: work_item.severity } }

      it 'does not assign the severity attributes' do
        expect { update_severity }.not_to change { IssuableSeverity.count }
      end
    end

    context 'when severity param is not present' do
      let(:params) { {} }

      it 'does not update the severity' do
        expect { update_severity }.not_to change { work_item.reload.severity }
      end
    end

    context 'when user is a planner, who cannot admin incidents' do
      let_it_be(:planner) { create(:user, planner_of: project) }
      let(:current_user) { planner }

      it 'does not update the severity' do
        expect { update_severity }.not_to change { work_item.reload.severity }
      end
    end
  end
end
