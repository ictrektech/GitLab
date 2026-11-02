# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ExportCsvWorker, feature_category: :team_planning do
  it 'does not enqueue an export' do
    expect(IssuableExportCsvWorker).not_to receive(:perform_async)

    described_class.new.perform(non_existing_record_id, non_existing_record_id, {})
  end
end
