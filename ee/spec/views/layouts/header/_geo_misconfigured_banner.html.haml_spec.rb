# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'layouts/header/_geo_misconfigured_banner', feature_category: :geo_replication do
  context 'when the banner should be shown' do
    before do
      allow(view).to receive_messages(
        show_geo_misconfigured_banner?: true,
        geo_configured_node_name: 'Wrong name'
      )
    end

    it 'renders the alert with the configured name and both links' do
      render

      expect(rendered).to have_css('[data-testid="geo-misconfigured-banner"]')
      expect(rendered).to have_content(s_('Geo|This site cannot find its own Geo site record'))
      expect(rendered).to have_css('code', text: 'Wrong name')
      expect(rendered).to have_link(
        s_('Geo|Learn how to fix this'),
        href: help_page_path(
          'administration/geo/replication/troubleshooting/common.md',
          anchor: 'can-geo-detect-the-current-site-correctly'
        )
      )
      expect(rendered).to have_link(s_('Geo|Go to Geo sites'), href: admin_geo_nodes_path)
    end

    it 'escapes the configured name', :skip_html_escaped_tags_check do
      allow(view).to receive(:geo_configured_node_name).and_return('<script>alert(1)</script>')

      render

      expect(rendered).not_to include('<script>')
    end
  end

  context 'when the banner should not be shown' do
    before do
      allow(view).to receive(:show_geo_misconfigured_banner?).and_return(false)
    end

    it 'renders nothing' do
      render

      expect(rendered).not_to have_css('[data-testid="geo-misconfigured-banner"]')
    end
  end
end
