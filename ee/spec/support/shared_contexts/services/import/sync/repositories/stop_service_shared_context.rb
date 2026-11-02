# frozen_string_literal: true

# Replaces the application lease with doubles and records the UPDATEs on the repository row. The including spec
# defines `repository`.
RSpec.shared_context 'with import sync stop service helpers' do
  let(:lease) { instance_double(Import::Sync::Repositories::ApplicationLease) }
  let(:lease_context) do
    instance_double(
      Import::Sync::Repositories::ApplicationLease::Context,
      verify_repository!: true,
      renew!: true
    )
  end

  before do
    allow(Import::Sync::Repositories::ApplicationLease).to receive(:new).with(repository.id).and_return(lease)
    allow(lease).to receive(:execute).and_yield(lease_context)
  end

  def repository_updates(&block)
    ActiveRecord::QueryRecorder.new(&block).log.select { |sql| sql.include?('UPDATE "import_sync_repositories"') }
  end
end
