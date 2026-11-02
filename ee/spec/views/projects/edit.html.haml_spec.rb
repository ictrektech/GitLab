# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/edit' do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:organization) { create(:organization) }
  let_it_be(:project) { create(:project, organization: organization) }
  let_it_be(:user) { create(:admin) }

  shared_context 'with settings for project admins' do
    where(:setting_text) do
      [
        _('Naming, description, topics'),
        s_('ProjectSettings|GitLab Duo')
      ]
    end

    before do
      stub_licensed_features(ai_features: true)
    end
  end

  before do
    assign(:project, project)

    allow(controller).to receive(:current_user).and_return(user)
    allow(view).to receive_messages(current_user: user,
      current_application_settings: Gitlab::CurrentSettings.current_application_settings)
  end

  context 'when rendering for a project admin' do
    before do
      allow(view).to receive_messages(can?: true)
    end

    describe 'settings for project admins' do
      subject do
        render
        rendered
      end

      include_context 'with settings for project admins'

      with_them do
        it { is_expected.to have_text(setting_text) }
      end
    end
  end

  context 'when rendering for a user that is not an owner', feature_category: :permissions do
    let(:user) { build_stubbed(:user) }
    let(:can_archive_projects) { false }
    let(:can_remove_projects) { false }

    before do
      allow(view).to receive(:can?).with(user, :archive_project, project).and_return(can_archive_projects)
      allow(view).to receive(:can?).with(user, :remove_project, project).and_return(can_remove_projects)
      render
    end

    subject { rendered }

    it { is_expected.not_to have_link(_('Archive project')) }
    it { is_expected.not_to have_text(_('Delete project')) }

    shared_examples 'does not render settings for project admins' do
      include_context 'with settings for project admins'

      with_them do
        it { is_expected.not_to have_text(setting_text) }
      end
    end

    context 'when the user can archive projects' do
      let(:can_archive_projects) { true }

      it { is_expected.to have_selector('#js-archive-settings') }

      it_behaves_like 'does not render settings for project admins'
    end

    context 'when the user can remove projects' do
      let(:can_remove_projects) { true }

      it { is_expected.to have_text(_('Delete project')) }

      it_behaves_like 'does not render settings for project admins'
    end
  end
end
