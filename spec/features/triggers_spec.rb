# frozen_string_literal: true

require 'spec_helper'

# Rendering the list, revealing token values and editing a description are covered by the
# frontend integration spec in ee/spec/frontend/integration/ci/pipeline_triggers/. This spec
# keeps the flows that round-trip through the server-rendered form and rails-ujs.
RSpec.describe 'Triggers', :js, feature_category: :continuous_integration do
  include Spec::Support::Helpers::ModalHelpers

  let(:trigger_title) { 'trigger desc' }
  let_it_be(:user) { create(:user) }
  let_it_be(:user2) { create(:user) }
  let_it_be(:project) { create(:project) }

  before_all do
    project.add_maintainer(user)
    project.add_maintainer(user2)
  end

  describe 'triggers page' do
    describe 'create trigger workflow' do
      before do
        sign_in(user)

        visit project_settings_ci_cd_path(project)

        wait_for_requests
      end

      it 'prevents adding new trigger with no description' do
        click_button 'Add new token'
        expect(page.find('#trigger_description')['placeholder']).to eq 'Trigger description'

        fill_in 'trigger_description', with: ''
        click_button 'Create pipeline trigger token'

        # See if input has error due to empty value
        expect(page.find('form.gl-show-field-errors .gl-field-error')).to be_visible
      end

      it 'adds new trigger with description' do
        click_button 'Add new token'
        fill_in 'trigger_description', with: 'trigger desc'
        click_button 'Create pipeline trigger token'

        aggregate_failures 'display creation notice and trigger is created' do
          expect(find_by_testid('alert-info')).to have_content 'Trigger token was created successfully.'
          expect(page.find('.triggers-list')).to have_content 'trigger desc'
          expect(page.find('.triggers-list .trigger-owner')['title']).to eq user.name
        end
      end

      context 'when trigger is not saved' do
        before do
          allow_next_instance_of(Ci::PipelineTriggers::CreateService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(
                message: 'Validation error',
                payload: { trigger: { description: ['is missing'] } },
                reason: :validation_error
              )
            )
          end
        end

        it 'trigger.errors has an error' do
          click_button 'Add new token'
          fill_in 'trigger_description', with: 'trigger desc'
          click_button 'Create pipeline trigger token'

          expect(page.find('.flash-container')).to(
            have_content("Validation error")
          )
        end
      end
    end

    describe 'trigger "Revoke" workflow' do
      before do
        create(:ci_trigger, owner: user2, project: project, description: trigger_title)

        sign_in(user)

        visit project_settings_ci_cd_path(project)

        wait_for_requests
      end

      it 'button "Revoke" has correct alert' do
        expected_alert = 'By revoking a trigger token you will break any processes making use of it. Are you sure?'
        expect(find_by_testid('trigger_revoke_button')['data-confirm']).to eq expected_alert
      end

      it 'revoke trigger' do
        # See if "Revoke" on trigger works post trigger creation
        accept_gl_confirm(button_text: 'Revoke') do
          find_by_testid('trigger_revoke_button').send_keys(:return)
        end

        aggregate_failures 'trigger is removed' do
          expect(find_by_testid('alert-info')).to have_content 'Trigger token removed'
          expect(page).to have_css('[data-testid="no_triggers_content"]')
        end
      end

      context 'when an error occurs' do
        before do
          allow_next_instance_of(Ci::PipelineTriggers::DestroyService) do |instance|
            allow(instance).to receive(:execute).and_return(
              ServiceResponse.error(
                message: 'An error occurred',
                reason: :validation_error
              )
            )
          end

          accept_gl_confirm(button_text: 'Revoke') do
            find_by_testid('trigger_revoke_button').send_keys(:return)
          end
        end

        it 'flashes an error' do
          expect(page.find('.flash-container')).to(
            have_content("An error occurred")
          )
        end
      end
    end
  end
end
