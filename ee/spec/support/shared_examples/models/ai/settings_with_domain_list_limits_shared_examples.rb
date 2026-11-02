# frozen_string_literal: true

# Requires `setting` (a persisted record) and `feature_flag_actor`.
RSpec.shared_examples 'settings with domain list limits' do
  let(:max_length_domain) { "#{'a' * 249}.com" }
  let(:too_long_domain) { "#{'a' * 250}.com" }

  def domains(count)
    Array.new(count) { |i| "domain-#{i}.com" }
  end

  it 'does not check the feature flag when neither list changes' do
    expect(Feature).not_to receive(:enabled?).with(:ai_domain_settings_list_limits, anything)

    expect(setting).to be_valid
  end

  it 'adds each error once when both lists exceed the limits' do
    setting.allowed_domains = domains(501) + [too_long_domain]
    setting.denied_domains = domains(501) + [too_long_domain]

    expect(setting).not_to be_valid
    expect(setting.errors[:base]).to contain_exactly(
      'Each domain list can contain at most 500 domains.',
      'Each domain can be at most 253 characters long.'
    )
  end

  { allowed_domains: :denied_domains, denied_domains: :allowed_domains }.each do |attribute, other_attribute|
    context "for #{attribute}" do
      it 'accepts 500 domains of up to 253 characters' do
        setting.public_send(:"#{attribute}=", domains(499) + [max_length_domain])

        expect(setting).to be_valid
      end

      it 'rejects more than 500 domains' do
        setting.public_send(:"#{attribute}=", domains(501))

        expect(setting).not_to be_valid
        expect(setting.errors[:base]).to include('Each domain list can contain at most 500 domains.')
      end

      it 'rejects domains longer than 253 characters' do
        setting.public_send(:"#{attribute}=", [too_long_domain])

        expect(setting).not_to be_valid
        expect(setting.errors[:base]).to include('Each domain can be at most 253 characters long.')
      end

      context 'when the saved list already exceeds the limits' do
        let(:saved_domains) { domains(501) + [too_long_domain] }

        before do
          setting.update_column(attribute, saved_domains)
        end

        it 'accepts changes to other attributes' do
          setting.public_send(:"#{other_attribute}=", ['example.com'])

          expect(setting).to be_valid
        end

        it 'accepts removing domains' do
          setting.public_send(:"#{attribute}=", saved_domains.drop(1))

          expect(setting).to be_valid
        end

        it 'rejects adding domains' do
          setting.public_send(:"#{attribute}=", saved_domains + ['example.com'])

          expect(setting).not_to be_valid
          expect(setting.errors[:base]).to include('Each domain list can contain at most 500 domains.')
        end
      end

      context 'when ai_domain_settings_list_limits is enabled only for the owning actor' do
        before do
          stub_feature_flags(ai_domain_settings_list_limits: feature_flag_actor)
        end

        it 'enforces the limits' do
          setting.public_send(:"#{attribute}=", domains(501))

          expect(setting).not_to be_valid
        end
      end

      context 'when ai_domain_settings_list_limits is disabled' do
        before do
          stub_feature_flags(ai_domain_settings_list_limits: false)
        end

        it 'does not enforce the limits' do
          setting.public_send(:"#{attribute}=", domains(501) + [too_long_domain])

          expect(setting).to be_valid
        end
      end
    end
  end
end
