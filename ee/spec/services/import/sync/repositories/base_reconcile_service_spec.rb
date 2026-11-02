# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::BaseReconcileService, feature_category: :importers do
  let(:repository) { create(:import_sync_repository, :oauth) }
  let(:lease_context) do
    instance_double(Import::Sync::Repositories::ApplicationLease::Context, verify_repository!: true)
  end

  def execute(service_class)
    service_class
      .new(repository, application_generation: repository.application_generation)
      .execute(lease_context: lease_context)
  end

  it 'requires a subclass to implement the reconciliation pass' do
    expect { execute(described_class) }.to raise_error(NotImplementedError)
  end

  it 'requires a subclass to implement failure recording' do
    service_class = Class.new(described_class) do
      private

      def reconcile_under_lease(_lease_context)
        raise StandardError, 'pass failed'
      end
    end

    expect { execute(service_class) }.to raise_error(NotImplementedError)
  end
end
