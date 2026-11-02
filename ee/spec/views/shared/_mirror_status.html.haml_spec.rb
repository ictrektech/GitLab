# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'shared/_mirror_status.html.haml', feature_category: :source_code_management do
  include ApplicationHelper

  let(:user) { build_stubbed(:user) }
  let(:timestamp) { Time.current }
  let(:project) { build_stubbed(:project, :mirror, import_state: import_state) }

  before do
    @project = project # for the view

    allow(view).to receive(:current_user).and_return(user)
    allow(project).to receive(:max_member_access_for_user).with(user).and_return(Gitlab::Access::OWNER)
  end

  context 'when mirror has not updated yet' do
    let(:import_state) { build_stubbed(:import_state) }

    it 'does not render anything' do
      render 'shared/mirror_status'

      expect(rendered).to be_empty
    end
  end

  context 'when mirror successful' do
    let(:import_state) do
      build_stubbed(:import_state, :finished, last_update_at: timestamp, last_successful_update_at: timestamp)
    end

    it 'renders success message' do
      render 'shared/mirror_status'

      expect(rendered).to have_content("Pull mirroring updated")
    end
  end

  context 'when project is read-only' do
    let(:import_state) do
      build_stubbed(:import_state, :finished, last_update_at: timestamp, last_successful_update_at: timestamp)
    end

    let(:project) { build_stubbed(:project, :mirror, import_state: import_state, repository_read_only: true) }

    it 'renders read-only message' do
      render 'shared/mirror_status'

      expect(rendered).to have_content("Pull mirroring is disabled because the repository is set to read-only.")
    end
  end

  context 'when mirror failed' do
    let(:import_state) { build_stubbed(:import_state, :failed, last_update_at: timestamp) }

    it 'renders failure message' do
      render 'shared/mirror_status', raw_message: true

      expect(rendered).to have_content("Pull mirroring failed")
    end

    it 'renders failure message with icon' do
      render 'shared/mirror_status'

      expect(rendered).to have_content("Pull mirroring failed")

      expect(rendered).to have_selector('[data-testid="warning-solid-icon"]')
    end

    context 'with a previous successful update' do
      let(:import_state) do
        build_stubbed(
          :import_state, :failed, last_update_at: timestamp, last_successful_update_at: timestamp - 1.minute
        )
      end

      it 'renders failure message' do
        render 'shared/mirror_status', raw_message: true

        expect(rendered).to have_content("Last successful update")
      end
    end

    context 'with a hard failed mirror' do
      let(:import_state) do
        build_stubbed(:import_state, :failed, last_update_at: timestamp, retry_count: Gitlab::Mirror::MAX_RETRY + 1)
      end

      it 'renders hard failed message' do
        render 'shared/mirror_status', raw_message: true

        expect(rendered).to have_content("Repository mirroring has been paused due to too many failed attempts. It can be resumed by a project maintainer or owner.")
      end
    end
  end
end
