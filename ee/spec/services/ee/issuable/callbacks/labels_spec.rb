# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Issuable::Callbacks::Labels, feature_category: :team_planning do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, reporters: user) }
  let_it_be(:archived_scoped_label) do
    create(:label, :archived, project: project, title: 'status::old')
  end

  let_it_be(:active_scoped_label) { create(:label, project: project, title: 'status::new') }
  let_it_be(:different_scoped_label) { create(:label, project: project, title: 'priority::high') }
  let_it_be(:active_label) { create(:label, project: project) }

  subject(:apply_labels) do
    described_class.new(issuable: issuable, current_user: user, params: params).after_initialize
  end

  before do
    stub_licensed_features(scoped_labels: true)
  end

  context 'when adding an active label from the same scope' do
    let(:issuable) { create(:issue, project: project, labels: [archived_scoped_label]) }
    let(:params) { { add_label_ids: [active_scoped_label.id] } }

    it 'replaces the existing archived scoped label' do
      apply_labels

      expect(issuable.reload.labels).to contain_exactly(active_scoped_label)
    end
  end

  context 'when adding an active label from a different scope' do
    let(:issuable) { create(:issue, project: project, labels: [archived_scoped_label]) }
    let(:params) { { add_label_ids: [different_scoped_label.id] } }

    it 'preserves the existing archived scoped label' do
      apply_labels

      expect(issuable.reload.labels).to contain_exactly(archived_scoped_label, different_scoped_label)
    end
  end

  context 'when adding an archived scoped label' do
    let(:issuable) { create(:issue, project: project, labels: [active_label]) }
    let(:params) { { add_label_ids: [archived_scoped_label.id] } }

    it 'does not add it' do
      apply_labels

      expect(issuable.reload.labels).to contain_exactly(active_label)
    end
  end
end
