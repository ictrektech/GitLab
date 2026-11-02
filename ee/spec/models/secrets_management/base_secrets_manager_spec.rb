# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::BaseSecretsManager, feature_category: :secrets_management do
  let(:manager_class) do
    Class.new(described_class) do
      self.table_name = 'project_secrets_managers'
    end
  end

  describe '.sticking_namespace' do
    it 'must be implemented' do
      expect { manager_class.sticking_namespace }.to raise_error(NotImplementedError)
    end
  end

  describe '#sticking_id' do
    it 'must be implemented' do
      expect { manager_class.new.sticking_id }.to raise_error(NotImplementedError)
    end
  end
end
