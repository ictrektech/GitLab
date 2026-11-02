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
      let(:maintainer) { create(:user) }

      context 'when creating a project secret' do
        before do
          project.add_member(maintainer, Resource::Members::AccessLevel::MAINTAINER)
        end

        it 'successfully creates a secret when Maintainer has create permissions' do
          Flow::Login.while_signed_in(as: owner) do
            project.visit!

            Page::Project::Menu.perform(&:go_to_general_settings)
            Page::Project::Settings::Main.perform do |settings|
              settings.expand_visibility_project_features_permissions do |permissions_page|
                scopes = %w[read create update]
                permissions_page.add_role_permission(role_name: 'Maintainer', scopes: scopes)
              end
            end
          end

          Flow::Login.while_signed_in(as: maintainer) do
            project.visit!

            Page::Project::Menu.perform(&:go_to_secrets_manager)
            EE::Page::Project::Secure::SecretsManager.perform do |secrets_page|
              secret_name = "test_maintainer_secret"

              expect(secrets_page).to have_new_secret_button
              secrets_page.click_new_secret
              secrets_page.create_secret(
                name: secret_name,
                value: 'testvalue',
                description: "Secret by test_maintainer_secret",
                environment: '*',
                branch: 'main'
              )

              expect(secrets_page).to have_secret_in_table(secret_name)
            end
          end
        end
      end
    end
  end
end
