# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DuoChatPanel::AccessDeniedComponent, :aggregate_failures, feature_category: :duo_chat do
  let(:user_namespace) { build_stubbed(:namespace) }
  let(:user) { build_stubbed(:user, namespace: user_namespace) }
  let(:record) { nil }
  let(:root_ancestor) { nil }
  let(:container) do
    instance_double(
      DuoChatPanel::Container, type: container_type, record: record, root_ancestor: root_ancestor
    )
  end

  let(:container_type) { 'group' }

  subject(:component) { render_inline(described_class.new(container: container, user: user)) && page }

  describe 'rendering' do
    it 'renders the #duo-chat-panel.duo-chat-panel element' do
      is_expected.to have_selector('#duo-chat-panel.duo-chat-panel')
    end

    it 'sets the access-denied data attribute' do
      is_expected.to have_css('#duo-chat-panel[data-access-denied="true"]')
    end

    context 'when container has no record (nil)' do
      it 'defaults the container-type data attribute to group' do
        is_expected.to have_css('#duo-chat-panel[data-container-type="group"]')
      end
    end

    context 'when within a project' do
      let(:record) { build(:project) }
      let(:container_type) { 'project' }

      it 'sets the correct container-type data attribute' do
        is_expected.to have_css('#duo-chat-panel[data-container-type="project"]')
      end
    end

    context 'when within a group' do
      let(:record) { build(:group) }
      let(:container_type) { 'group' }

      it 'sets the correct container-type data attribute' do
        is_expected.to have_css('#duo-chat-panel[data-container-type="group"]')
      end
    end
  end

  describe 'auto_expand field' do
    it 'is "false" even though the user has not dismissed the auto-expand callout' do
      is_expected.to have_css('#duo-chat-panel[data-auto-expand="false"]')
    end
  end

  describe 'request GitLab Duo eligibility' do
    let(:root_ancestor) { root_group }
    let(:root_group) { build_stubbed(:group) }
    let(:requested) { false }
    let(:eligibility) do
      instance_double(
        GitlabSubscriptions::PaintedDoorRequestEligibility,
        eligible?: eligible, root: root_group, requested?: requested
      )
    end

    before do
      allow(GitlabSubscriptions::PaintedDoorRequestEligibility).to receive(:new)
        .with(user: user, namespace: root_ancestor, feature: :duo_panel)
        .and_return(eligibility)
    end

    context 'when eligible' do
      let(:eligible) { true }

      it 'sets the request-duo-group-id and request-duo-requested data attributes' do
        is_expected.to have_css("#duo-chat-panel[data-request-duo-group-id=\"#{root_group.id}\"]")
        is_expected.to have_css('#duo-chat-panel[data-request-duo-requested="false"]')
      end

      context 'when the user already requested it' do
        let(:requested) { true }

        it 'sets request-duo-requested to "true"' do
          is_expected.to have_css('#duo-chat-panel[data-request-duo-requested="true"]')
        end
      end
    end

    context 'when not eligible' do
      let(:eligible) { false }

      it 'does not set the request-duo data attributes' do
        is_expected.not_to have_css('[data-request-duo-group-id]')
        is_expected.not_to have_css('[data-request-duo-requested]')
      end
    end
  end
end
