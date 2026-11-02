# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'shared/issuable/_sidebar.html.haml' do
  let(:user) { build_stubbed(:user) }

  subject(:rendered) do
    render 'shared/issuable/sidebar', issuable_sidebar: IssueSerializer.new(current_user: user)
      .represent(issuable, serializer: 'sidebar'), assignees: []
  end

  context 'project in a group' do
    let(:group) { build_stubbed(:group) }
    let(:project) { build_stubbed(:project, group: group) }
    let(:issue) { build_stubbed(:issue, project: project) }
    let(:incident) { build_stubbed(:incident, project: project) }

    before do
      assign(:project, project)
    end

    context 'when issuable is an issue' do
      let(:issuable) { issue }

      it 'shows iteration dropdown' do
        expect(rendered).to have_css('[data-testid="iteration-container"]')
      end
    end

    context 'when issuable is an incident' do
      let(:issuable) { incident }

      it 'shows iteration dropdown' do
        expect(rendered).to have_css('[data-testid="iteration-container"]')
      end
    end

    context 'issuable that does not support escalation policies' do
      let(:issuable) { incident }

      before do
        stub_licensed_features(oncall_schedules: true, escalation_policies: true)
      end

      it 'shows escalation policy dropdown' do
        expect(rendered).to have_css('[data-testid="escalation_policy_container"]')
      end
    end

    context 'issuable that supports escalation policies' do
      let(:issuable) { issue }

      it 'does not show escalation policy dropdown' do
        expect(rendered).not_to have_css('[data-testid="escalation_policy_container"]')
      end
    end
  end

  context 'non-group project' do
    let_it_be(:project) { create(:project) }

    let(:issuable) { create(:issue, project: project) }

    before do
      assign(:project, project)
    end

    it 'does not show iteration dropdown' do
      expect(rendered).not_to have_css('[data-testid="iteration-container"]')
    end
  end
end
