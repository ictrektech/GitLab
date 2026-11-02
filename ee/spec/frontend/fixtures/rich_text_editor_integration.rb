# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rich text editor Integration (preview fixtures)', type: :request, feature_category: :markdown do
  include JavaScriptFixturesHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, maintainers: user) }
  let_it_be(:referenced_user) { create(:user, :with_namespace, name: 'abc123', username: 'abc123') }

  let(:upload_secret) { '0123456789abcdef0123456789abcdef' }

  before do
    stub_config_setting(host: 'gitlab.example.com')
    allow(FileUploader).to receive(:generate_secret).and_return(upload_secret)
    sign_in(user)
  end

  describe 'preview_markdown' do
    let(:preview_params) { { target_type: 'WorkItem', render_quick_actions: 'true', no_header_anchors: 'false' } }
    let(:snippets) do
      [
        'Undo keeps this text',
        'Server: %{gitlab_server}',
        '%{gitlab_server}',
        'The energy is $E = mc^2$ here',
        "| First Header | Second Header |\n|--------------|---------------|\n" \
          "| Content from cell 1 | Content from cell 2 |\n\nContent below table",
        "- [ ] checklist\n  - [ ] nested checklist\n  - [ ] nested checklist 2",
        "| header | header |\n| ------ | ------ |\n|        |        |\n|        |        |",
        '@abc123 @abc123+ @abc123+s',
        '@nonexistentuser @nonexistentuser+ @nonexistentuser+s',
        'Typing text in the content editor',
        "```\nvar test1 10\n// testing comment\n/usr/bin/env bash\ntest 1\n```\n\nNotes",
        "[sample.pdf](/uploads/#{upload_secret}/sample.pdf)",
        '[link](https://gitlab.com)',
        '[link](https://about.gitlab.com)',
        '[link](https://en.wikipedia.org/wiki/Shiba_Inu)',
        'Some **rich** _text_ ~~content~~ [link](https://gitlab.com)',
        '* one',
        'one'
      ]
    end

    let(:previews) { {} }
    let(:response) { { params: preview_params, previews: previews }.to_json }

    it 'rich_text_editor/integration/preview_markdown.json' do
      snippets.each do |text|
        post project_preview_markdown_path(project, preview_params), params: { text: text }, as: :json

        expect(integration_session.response).to have_gitlab_http_status(:ok)

        previews[text] = integration_session.response.parsed_body
      end
    end
  end

  describe 'autocomplete sources' do
    it 'rich_text_editor/integration/autocomplete_members.json' do
      get members_project_autocomplete_sources_path(project, type: 'WorkItem')

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'rich_text_editor/integration/autocomplete_labels.json' do
      get labels_project_autocomplete_sources_path(project, type: 'WorkItem')

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  describe 'uploads' do
    it 'rich_text_editor/integration/upload_sample_pdf.json' do
      post project_uploads_path(project, format: :json),
        params: { file: fixture_file_upload('spec/fixtures/sample.pdf', 'application/pdf') }

      expect(response).to have_gitlab_http_status(:ok)
    end
  end
end
