# frozen_string_literal: true

# Expects `subject` to request a page rendered with a settings layout.
# Controller specs skip view rendering by default, which leaves the body empty
# and would make the "not include" check pass vacuously.
RSpec.shared_examples 'hides the settings search bar' do
  render_views if respond_to?(:render_views)

  it 'renders the page without the settings search bar', :aggregate_failures do
    subject

    expect(response).to have_gitlab_http_status(:ok)
    expect(response.body).to be_present
    expect(response.body).not_to include('js-search-settings-app')
  end
end
