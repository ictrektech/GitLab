# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'admin/application_settings/_sms_cost_restricted_dial_codes', feature_category: :instance_resiliency do
  let(:application_setting) { build(:application_setting, sms_cost_restricted_dial_codes: [44, 999]) }

  # `render` raises on partials that return early or use gitlab_ui_form_for, so render through the view directly
  subject(:rendered) { view.render('admin/application_settings/sms_cost_restricted_dial_codes') }

  before do
    view.instance_variable_set(:@application_setting, application_setting)
  end

  context 'when identity verification is available', :saas_identity_verification do
    it 'renders a checkbox per dial code with restricted codes checked', :aggregate_failures do
      expect(rendered).to have_checked_field('+44')
      expect(rendered).to have_unchecked_field('+93')
      expect(rendered).to have_field('application_setting[sms_cost_restricted_dial_codes][]', type: :hidden)
    end

    it 'renders a row per country sharing a dial code', :aggregate_failures do
      rows = Capybara.string(rendered).all('[data-testid="dial-code-44-row"]').map(&:text)

      expect(rows.size).to eq(4)
      expect(rows.last).to include('United Kingdom of Great Britain and Northern Ireland', 'GB')
    end

    it 'renders a restricted dial code that matches no supported country' do
      expect(rendered).to have_css('[data-testid="dial-code-999-row"]', text: 'No supported country')
    end

    it 'shows the number of restricted dial codes' do
      expect(rendered).to have_css('[data-testid="crud-count"]', text: '2')
    end
  end

  context 'when identity verification is unavailable' do
    it 'renders nothing' do
      expect(rendered).to be_nil
    end
  end
end
