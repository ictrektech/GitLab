# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::IamReplication::HashedSecret, feature_category: :system_access do
  using RSpec::Parameterized::TableSyntax

  describe '.of' do
    where(:value, :expected) do
      Gitlab::DoorkeeperSecretStoring::Sha512Hash.transform_secret('test-secret')   | ref(:value)
      Gitlab::DoorkeeperSecretStoring::Pbkdf2Sha512.transform_secret('test-secret') | ref(:value)
      'test-secret' | Gitlab::DoorkeeperSecretStoring::Sha512Hash.transform_secret('test-secret')
    end

    with_them do
      it 'returns a digest IAM accepts' do
        expect(described_class.of(value)).to eq(expected)
      end
    end
  end
end
