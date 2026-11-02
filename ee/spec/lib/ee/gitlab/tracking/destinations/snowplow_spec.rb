# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Tracking::Destinations::Snowplow, :do_not_stub_snowplow_by_default, feature_category: :application_instrumentation do
  describe '.dedicated?' do
    context 'when the instance is a Dedicated instance', :dedicated do
      it 'returns true' do
        expect(described_class.dedicated?).to be(true)
      end
    end

    context 'when not a Dedicated instance' do
      it 'returns false' do
        expect(described_class.dedicated?).to be(false)
      end
    end
  end

  describe '#app_id' do
    let(:app_id_suffix) { '' }
    let(:destination_configuration) do
      Gitlab::Tracking::Destinations::DestinationConfiguration.new(
        URI('https://example.com'), app_id_suffix: app_id_suffix
      )
    end

    subject(:snowplow) { described_class.new(destination_configuration) }

    before do
      stub_application_setting(snowplow_enabled?: false)
    end

    context 'when dedicated instance', :dedicated do
      it 'returns gitlab_dedicated' do
        expect(snowplow.app_id).to eq('gitlab_dedicated')
      end

      context 'when staging' do
        before do
          allow(Gitlab).to receive(:staging?).and_return(true)
        end

        it 'returns gitlab_dedicated_staging' do
          expect(snowplow.app_id).to eq('gitlab_dedicated_staging')
        end
      end

      context 'when on Dedicated QA host' do
        before do
          stub_config_setting(host: 'gitlab-test.example.test')
        end

        it 'returns gitlab_dedicated_staging' do
          expect(snowplow.app_id).to eq('gitlab_dedicated_staging')
        end
      end

      context 'with app_id_suffix' do
        let(:app_id_suffix) { '_billing' }

        it 'appends the suffix to gitlab_dedicated' do
          expect(snowplow.app_id).to eq('gitlab_dedicated_billing')
        end

        context 'when staging' do
          before do
            allow(Gitlab).to receive(:staging?).and_return(true)
          end

          it 'appends suffix before staging' do
            expect(snowplow.app_id).to eq('gitlab_dedicated_billing_staging')
          end
        end

        context 'when on Dedicated QA host' do
          before do
            stub_config_setting(host: 'gitlab-test.example.test')
          end

          it 'appends suffix before staging' do
            expect(snowplow.app_id).to eq('gitlab_dedicated_billing_staging')
          end
        end
      end
    end
  end
end
