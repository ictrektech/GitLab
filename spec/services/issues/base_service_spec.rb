# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Issues::BaseService, feature_category: :team_planning do
  describe '.constructor_container_arg' do
    it { expect(described_class.constructor_container_arg("some-value")).to eq({ container: "some-value" }) }
  end

  describe '#available_callbacks' do
    let_it_be(:project) { create(:project) }

    subject(:service) { described_class.new(container: project, current_user: project.owner, params: {}) }

    specify do
      expect(service.available_callbacks).to include(
        ::WorkItems::Callbacks::StartAndDueDate
      )
    end
  end

  describe '#enforce_work_item_type_availability?' do
    let_it_be(:project) { create(:project) }

    subject(:service) { described_class.new(container: project, current_user: project.owner, params: {}) }

    it 'is enabled by the flag when the issue has no namespace' do
      issue = build(:issue)
      allow(issue).to receive(:namespace).and_return(nil)

      expect(service.send(:enforce_work_item_type_availability?, issue)).to be(true)
    end
  end

  describe '#check_work_item_type_availability!' do
    let_it_be(:project) { create(:project) }
    let_it_be(:issue) { create(:issue, project: project) }

    subject(:service) { described_class.new(container: project, current_user: project.owner, params: {}) }

    it 'skips persisted issues' do
      expect(service).not_to receive(:enforce_work_item_type_availability?)

      service.send(:check_work_item_type_availability!, issue)
    end

    it 'does not raise when the type cannot be resolved' do
      new_issue = build(:issue, project: project)
      allow(new_issue).to receive(:work_item_type_id).and_return(non_existing_record_id)

      expect { service.send(:check_work_item_type_availability!, new_issue) }.not_to raise_error
    end
  end

  describe Issues::BaseService::WorkItemTypeUnavailableError do
    subject(:error) { described_class.new(build(:issue), 'Issue is disabled or archived for this project or group.') }

    it 'keeps the bare text as the attribute message and prefixes the attribute name in the message' do
      expect(error.attribute_message).to eq('Issue is disabled or archived for this project or group.')
      expect(error.message).to eq('Work item type Issue is disabled or archived for this project or group.')
    end
  end
end
