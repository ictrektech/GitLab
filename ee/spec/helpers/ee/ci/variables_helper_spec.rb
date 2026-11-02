# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::Ci::VariablesHelper, feature_category: :secrets_management do
  describe '#ci_variables_secrets_manager_cta_in_variables_data' do
    let(:entity) { build_stubbed(:project) }

    subject(:data) { helper.ci_variables_secrets_manager_cta_in_variables_data(entity) }

    # The decision logic is covered in `SecretsHelper#secrets_manager_variables_cta_data`.
    before do
      allow(helper).to receive(:secrets_manager_variables_cta_data).with(entity).and_return(cta_data)
    end

    context 'when there is a card to show' do
      let(:cta_data) { { secrets_manager_available: true, secrets_path: '/secrets' } }

      it 'serializes the CTA data as JSON for the data attribute' do
        expect(Gitlab::Json::SafeParser.parse(data))
          .to eq('secrets_manager_available' => true, 'secrets_path' => '/secrets')
      end
    end

    context 'when there is no card to show' do
      let(:cta_data) { {} }

      it { is_expected.to be_nil }
    end
  end
end
