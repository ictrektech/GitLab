# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/_home_panel' do
  include ProjectForksHelper

  describe 'home panel' do
    let(:project) { build_stubbed(:project) }

    before do
      assign(:project, project)
    end

    it 'renders Vue app root in the panel header actions' do
      render

      expect(view.content_for(:static_panel_actions)).to have_selector('#js-home-panel')
    end

    it 'renders the project name' do
      render

      expect(rendered).to have_selector('[data-testid="project-name-content"]', text: project.name)
    end

    it 'hides the project avatar from assistive technology' do
      render

      expect(rendered).to have_selector('.gl-avatar-identicon[aria-hidden="true"]')
    end
  end

  describe 'forks' do
    let(:source_project) { create(:project) }
    let(:project) { fork_project(source_project) }
    let(:user) { build_stubbed(:user) }

    before do
      assign(:project, project)

      allow(view).to receive(:current_user).and_return(user)
    end

    context 'when user can read fork source' do
      before do
        allow(view).to receive(:can?).with(user, :read_project, source_project).and_return(true)
      end

      it 'does not show the forked-from project' do
        render

        expect(rendered).not_to have_content("Forked from #{source_project.full_name}")
      end
    end

    context 'when user cannot read fork source' do
      before do
        allow(view).to receive(:can?).with(user, :read_project, source_project).and_return(false)
      end

      it 'shows the message that forked project is inaccessible' do
        render

        expect(rendered).not_to have_content("Forked from an inaccessible project")
      end
    end
  end
end
