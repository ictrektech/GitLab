# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::Licenses::BillableUsageExportsController, :enable_admin_mode,
  feature_category: :consumables_cost_management do
  let_it_be(:admin) { create(:admin) }

  let_it_be(:license) do
    create_current_license(cloud_licensing_enabled: true, offline_cloud_licensing_enabled: true,
      starts_at: Date.new(2026, 8, 1), seats: 450)
  end

  let_it_be(:previous_license) do
    data = build(:gitlab_license, cloud_licensing_enabled: true, offline_cloud_licensing_enabled: true,
      starts_at: Date.new(2025, 8, 1), expires_at: Date.new(2026, 8, 1), seats: 400).export

    build(:license, data: data).tap { |license| license.save!(validate: false) }
  end

  let_it_be(:previous_term_daily_total) do
    create(:billable_usage_daily_total, usage_date: Date.new(2026, 7, 20), quantity: 8, events_count: 2)
  end

  let_it_be(:historical_data_1) do
    create(:historical_data, recorded_at: Time.utc(2026, 8, 5, 12, 0), active_user_count: 5)
  end

  let_it_be(:historical_data_2) do
    create(:historical_data, recorded_at: Time.utc(2026, 8, 10, 12, 0), active_user_count: 7)
  end

  let_it_be(:daily_total_1) do
    create(:billable_usage_daily_total, usage_date: Date.new(2026, 8, 5), quantity: 30, events_count: 5)
  end

  let_it_be(:daily_total_2) do
    create(:billable_usage_daily_total, usage_date: Date.new(2026, 8, 10), quantity: 5, events_count: 1)
  end

  let(:now) { Time.utc(2026, 8, 15, 10, 0) }

  around do |example|
    travel_to(now) { example.run }
  end

  before do
    sign_in(admin)
    stub_feature_flags(billable_usage_export: true)
    allow_next_instance_of(::Gitlab::BillingEvents::Client) do |client|
      allow(client).to receive(:local_persistence_enabled?).and_return(true)
    end
    Gitlab::CurrentSettings.update!(license_usage_data_exported: false)
  end

  shared_examples 'an export that is not available everywhere' do
    context 'without a current license' do
      before do
        allow(License).to receive(:current).and_return(nil)
      end

      it 'redirects the user' do
        request_export

        expect(response).to have_gitlab_http_status(:redirect)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(billable_usage_export: false)
      end

      it 'returns a 404' do
        request_export

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when local persistence is not enabled' do
      before do
        allow_next_instance_of(::Gitlab::BillingEvents::Client) do |client|
          allow(client).to receive(:local_persistence_enabled?).and_return(false)
        end
      end

      it 'returns a 404' do
        request_export

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when signed in as a non-admin' do
      let_it_be(:user) { create(:user) }

      before do
        sign_in(user)
      end

      it 'returns a 404' do
        request_export

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  shared_examples 'an export of a chosen term' do
    context 'when the license starts today' do
      let(:now) { Time.utc(2026, 8, 1, 10, 0) }

      it 'returns a 422 without recording an export', :aggregate_failures do
        expect { request_export }.not_to change { Utilization::BillableUsage::ExportLog.count }

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response['message']).to eq(s_('BillableUsageExport|There is no completed day to export yet'))
      end
    end

    context 'with a license_id outside the exportable terms' do
      let(:license_id) { non_existing_record_id }

      it 'returns a 404 without recording an export', :aggregate_failures do
        expect { request_export }.not_to change { Utilization::BillableUsage::ExportLog.count }

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  shared_examples 'an export whose build fails' do
    before do
      allow_next_instance_of(Utilization::BillableUsage::Exports::BuildPayloadService) do |service|
        allow(service).to receive(:execute).and_return(
          ServiceResponse.error(message: 'boom', reason: :file_too_large)
        )
      end
    end

    it 'returns a 422 with the error message', :aggregate_failures do
      request_export

      expect(response).to have_gitlab_http_status(:unprocessable_entity)
      expect(Gitlab::Json::SafeParser.parse(response.body)).to eq('message' => 'boom')
    end

    it 'does not record an export or mark the license usage data as exported', :aggregate_failures do
      expect { request_export }.not_to change { Utilization::BillableUsage::ExportLog.count }
      expect(Gitlab::CurrentSettings.reload.license_usage_data_exported).to be(false)
    end
  end

  describe 'GET terms' do
    subject(:request_export) { get terms_admin_license_billable_usage_export_path }

    it_behaves_like 'an export that is not available everywhere'

    it 'lists the current and the previous term, newest first', :aggregate_failures do
      request_export

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to eq([
        {
          'license_id' => license.id,
          'start_date' => '2026-08-01',
          'end_date' => (license.expires_at - 1).iso8601,
          'current' => true
        },
        {
          'license_id' => previous_license.id,
          'start_date' => '2025-08-01',
          'end_date' => '2026-07-31',
          'current' => false
        }
      ])
    end

    context 'when the license starts today' do
      let(:now) { Time.utc(2026, 8, 1, 10, 0) }

      it 'still lists the current term' do
        request_export

        expect(json_response.pluck('license_id')).to eq([license.id, previous_license.id])
      end
    end
  end

  describe 'GET show' do
    subject(:request_export) { get admin_license_billable_usage_export_path(license_id: license_id) }

    let(:license_id) { nil }

    it_behaves_like 'an export that is not available everywhere'
    it_behaves_like 'an export of a chosen term'
    it_behaves_like 'an export whose build fails'

    it 'returns the export document as JSON rather than as a file', :aggregate_failures do
      request_export

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.media_type).to eq('application/json')
      expect(response.headers['Content-Disposition']).to be_nil
    end

    it 'includes the summed records, matching coverage, checksum and identity', :aggregate_failures do
      request_export

      body = Gitlab::Json::SafeParser.parse(response.body)['document']

      expect(body['record_count']).to eq(2)
      expect(body['records'].size).to eq(2)
      expect(body['coverage']['seat_link']['days_with_data']).to eq(body['seat_link']['records'].size)
      expect(Utilization::BillableUsage::Exports::Checksum.digest(body)).to eq(body['checksum'])

      identity = Gitlab::BillingEvents::InstanceIdentity.to_h
      identity.each_key { |key| expect(body).to have_key(key.to_s) }
    end

    it 'previews the same document the download serves' do
      request_export
      previewed = Gitlab::Json::SafeParser.parse(response.body)['document']

      get download_admin_license_billable_usage_export_path

      expect(previewed).to eq(Gitlab::Json::SafeParser.parse(response.body))
    end

    it 'includes the term licensed seats and when it was last exported', :aggregate_failures do
      create(:billable_usage_export_log, period_start: Date.new(2026, 8, 1), period_end: Date.new(2026, 8, 10),
        generated_at: Time.utc(2026, 8, 11, 9, 12))

      request_export

      body = Gitlab::Json::SafeParser.parse(response.body)

      expect(body['licensed_seats']).to eq(450)
      expect(body['last_exported_at']).to eq('2026-08-11T09:12:00Z')
    end

    it 'covers the current term when no license_id is given', :aggregate_failures do
      request_export

      body = Gitlab::Json::SafeParser.parse(response.body)['document']

      expect(body).to include(
        'license_key' => license.normalized_data,
        'period_start' => '2026-08-01',
        'period_end' => '2026-08-14'
      )
    end

    context 'with the license_id of the previous term' do
      let(:license_id) { previous_license.id }

      it 'covers the whole previous term with its license key', :aggregate_failures do
        request_export

        body = Gitlab::Json::SafeParser.parse(response.body)['document']

        expect(response).to have_gitlab_http_status(:ok)
        expect(body).to include(
          'license_key' => previous_license.normalized_data,
          'period_start' => '2025-08-01',
          'period_end' => '2026-07-31',
          'record_count' => 1
        )
      end

      it 'includes the previous term licensed seats and no last export', :aggregate_failures do
        request_export

        body = Gitlab::Json::SafeParser.parse(response.body)

        expect(body['licensed_seats']).to eq(400)
        expect(body['last_exported_at']).to be_nil
      end
    end

    it 'does not record an export or mark the license usage data as exported', :aggregate_failures do
      expect { request_export }.not_to change { Utilization::BillableUsage::ExportLog.count }
      expect(Gitlab::CurrentSettings.reload.license_usage_data_exported).to be(false)
    end
  end

  describe 'GET download' do
    subject(:request_export) { get download_admin_license_billable_usage_export_path(license_id: license_id) }

    let(:license_id) { nil }

    it_behaves_like 'an export that is not available everywhere'
    it_behaves_like 'an export of a chosen term'
    it_behaves_like 'an export whose build fails'

    it 'returns the export as a JSON file attachment', :aggregate_failures do
      request_export

      filename = 'billable_usage_export_2026-08-01_2026-08-14.json'

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.headers['Content-Type']).to eq('application/json; charset=utf-8')
      expect(response.headers['Content-Disposition']).to include('attachment')
      expect(response.headers['Content-Disposition']).to include(filename)
    end

    it 'marks the license usage data as exported' do
      request_export

      expect(Gitlab::CurrentSettings.reload.license_usage_data_exported).to be(true)
    end

    context 'with the previous term' do
      let(:license_id) { previous_license.id }

      it 'records the export without marking the license usage data as exported', :aggregate_failures do
        expect { request_export }.to change { Utilization::BillableUsage::ExportLog.count }.by(1)

        expect(response).to have_gitlab_http_status(:ok)
        expect(Gitlab::CurrentSettings.reload.license_usage_data_exported).to be(false)
      end
    end

    it 'records the export it served', :aggregate_failures do
      expect { request_export }.to change { Utilization::BillableUsage::ExportLog.count }.by(1)

      body = Gitlab::Json::SafeParser.parse(response.body)
      export_log = Utilization::BillableUsage::ExportLog.last

      expect(export_log).to have_attributes(
        period_start: Date.parse(body['period_start']),
        period_end: Date.parse(body['period_end']),
        generated_at: Time.iso8601(body['generated_at']),
        generated_by: admin,
        record_count: body['record_count'],
        payload_checksum: body['checksum']
      )
    end

    context 'with the license_id of the previous term' do
      let(:license_id) { previous_license.id }

      it 'records the export against the previous term', :aggregate_failures do
        expect { request_export }.to change { Utilization::BillableUsage::ExportLog.count }.by(1)

        expect(response.headers['Content-Disposition']).to include('billable_usage_export_2025-08-01_2026-07-31.json')
        expect(Utilization::BillableUsage::ExportLog.last).to have_attributes(
          period_start: Date.new(2025, 8, 1),
          period_end: Date.new(2026, 7, 31)
        )
      end
    end

    context 'when the export cannot be recorded' do
      before do
        allow(Utilization::BillableUsage::ExportLog).to receive(:create!)
          .and_raise(ActiveRecord::RecordInvalid)
      end

      it 'does not serve the file or mark the license usage data as exported', :aggregate_failures do
        expect { request_export }.to raise_error(ActiveRecord::RecordInvalid)

        expect(response).to be_nil
        expect(Gitlab::CurrentSettings.reload.license_usage_data_exported).to be(false)
      end
    end

    context 'when compared to the seat usage export' do
      it 'still serves the CSV export and marks the license usage data as exported', :aggregate_failures do
        get admin_license_usage_export_path(format: :csv)

        expect(response).to have_gitlab_http_status(:ok)
        expect(Gitlab::CurrentSettings.reload.license_usage_data_exported).to be(true)
      end
    end
  end
end
