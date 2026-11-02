# frozen_string_literal: true

module QA
  RSpec.describe(
    'Software Supply Chain Security',
    :secrets_manager,
    :orchestrated,
    :requires_admin,
    feature_category: :secrets_management
  ) do
    include_context 'secrets manager base'
    describe 'Project Secret' do
      def reporter
        @reporter ||= create(:user)
      end

      before(:context) do
        project.add_member(reporter, Resource::Members::AccessLevel::REPORTER)
      end

      context 'when reading a project secret' do
        it 'shows the read denied alert when Reporter has no permissions' do
          Flow::Login.while_signed_in(as: reporter) do
            visit("#{project.web_url}/-/secrets")

            EE::Page::Project::Secure::SecretsManager.perform do |secrets_page|
              expect(secrets_page).to have_read_denied_alert
              # Checked after the alert, so the page has rendered.
              expect(secrets_page).to have_no_empty_state_new_secret_button
            end
          end
        end
      end
    end
  end
end
