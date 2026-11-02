# frozen_string_literal: true

require 'fast_spec_helper'
require 'webmock/rspec'

require_relative '../../../scripts/cells/check_router_routes_sync'

RSpec.describe CheckRouterRoutesSync, feature_category: :tooling do
  let(:snapshot_url) do
    'https://gitlab.com/api/v4/projects/gitlab-org%2Fcells%2Fhttp-router' \
      '/repository/files/test%2Froutes%2Fgitlab_routes.json/raw?ref=main'
  end

  let(:base_url) do
    'https://gitlab.com/api/v4/projects/gitlab-org%2Fgitlab' \
      '/repository/files/config%2Frouting%2Fgitlab_routes.json/raw?ref=master'
  end

  let(:env)            { {} }
  let(:local_payload)  { payload('/new') }
  let(:base_payload)   { payload }
  let(:router_payload) { local_payload }
  let(:router_status)  { 200 }
  let(:base_status)    { 200 }

  # SnapshotComparison::MIN_ROUTES rejects a short payload as a truncated
  # response, so pad each snapshot up to the floor.
  def payload(*templates)
    routes = Array.new(Gitlab::Cells::HttpRouter::SnapshotComparison::MIN_ROUTES) do |i|
      { 'template' => "/filler/#{i}", 'example' => "/filler/#{i}" }
    end
    routes += templates.map do |template|
      template.is_a?(Hash) ? template : { 'template' => template, 'example' => template }
    end

    "#{JSON.pretty_generate(routes)}\n" # rubocop:disable Gitlab/Json -- the script runs on plain Ruby, outside Rails
  end

  before do
    stub_const('ENV', env)
    described_class.instance_variable_set(:@snapshot_url, nil)
    described_class.instance_variable_set(:@base_snapshot_url, nil)

    allow(File).to receive(:read).and_call_original
    allow(File).to receive(:read).with(described_class.send(:local_path)).and_return(local_payload)

    stub_request(:get, snapshot_url).to_return(status: router_status, body: router_payload)
    stub_request(:get, base_url).to_return(status: base_status, body: base_payload)
  end

  describe '.run' do
    it 'downloads both snapshots and reports the router in sync' do
      expect { expect(described_class.run).to eq(described_class::IN_SYNC) }
        .to output(include('the HTTP Router has every route that this branch adds or changes')).to_stdout

      expect(a_request(:get, snapshot_url)).to have_been_made
      expect(a_request(:get, base_url)).to have_been_made
    end

    context 'when the router has routes this branch does not have' do
      let(:router_payload) { payload('/new', '/other-merge-request') }

      it 'reports the router in sync' do
        expect { expect(described_class.run).to eq(described_class::IN_SYNC) }.to output.to_stdout
      end
    end

    context 'when the router does not have a route this branch adds' do
      let(:router_payload) { payload('/other-merge-request') }

      it 'lists the route and reports drift' do
        expect { expect(described_class.run).to eq(described_class::DRIFT) }
          .to output(include("1 route templates added or changed on this branch are not in the HTTP Router:\n  /new"))
          .to_stderr
      end
    end

    context 'when the router has different fields for a route this branch changes' do
      let(:base_payload)   { payload({ 'template' => '/changed', 'example' => '/changed' }) }
      let(:local_payload)  { payload({ 'template' => '/changed', 'example' => '/changed', 'acceptsFormat' => true }) }
      let(:router_payload) { base_payload }

      it 'lists the route as outdated and reports drift' do
        expect { expect(described_class.run).to eq(described_class::DRIFT) }
          .to output(include(
            "1 route templates added or changed on this branch have different fields in the HTTP Router:\n  /changed"
          )).to_stderr
      end
    end

    context 'when the router snapshot cannot be downloaded' do
      let(:router_status)  { 404 }
      let(:router_payload) { '' }

      it 'reports a download failure, not drift' do
        expect { expect(described_class.run).to eq(described_class::DOWNLOAD_FAILED) }
          .to output(include(snapshot_url).and(include('DOWNLOAD FAILED'))).to_stderr
      end
    end

    context 'when the router returns a server error and then the snapshot' do
      before do
        allow(described_class).to receive(:sleep)
        stub_request(:get, snapshot_url).to_return({ status: 503 }, { status: 200, body: router_payload })
      end

      it 'retries the download and reports the router in sync' do
        expect { expect(described_class.run).to eq(described_class::IN_SYNC) }.to output.to_stdout

        expect(a_request(:get, snapshot_url)).to have_been_made.twice
        expect(described_class).to have_received(:sleep).with(1)
      end
    end

    context 'when the router returns a server error on every attempt' do
      let(:router_status)  { 503 }
      let(:router_payload) { '' }

      before do
        allow(described_class).to receive(:sleep)
      end

      it 'stops after the last attempt and reports a download failure' do
        expect { expect(described_class.run).to eq(described_class::DOWNLOAD_FAILED) }
          .to output(include("could not download #{snapshot_url}").and(include('returned HTTP 503'))).to_stderr

        expect(a_request(:get, snapshot_url)).to have_been_made.times(described_class::MAX_ATTEMPTS)
      end
    end

    context 'when the router snapshot is not a snapshot' do
      let(:router_payload) { '<!DOCTYPE html>' }

      it 'reports a download failure, not drift' do
        expect { expect(described_class.run).to eq(described_class::DOWNLOAD_FAILED) }
          .to output(
            include('HTTP Router snapshot is not valid JSON')
              .and(include('DOWNLOAD FAILED'))
              .and(include('If the file is not valid, retrying does not'))
          ).to_stderr
      end
    end

    context 'when the base snapshot cannot be downloaded' do
      let(:base_status)  { 404 }
      let(:base_payload) { '' }

      it 'reports a download failure, not drift' do
        expect { expect(described_class.run).to eq(described_class::DOWNLOAD_FAILED) }
          .to output(include(base_url).and(include('DOWNLOAD FAILED'))).to_stderr
      end
    end

    context 'when the base snapshot is not a snapshot' do
      let(:base_payload) { '<!DOCTYPE html>' }

      it 'reports a download failure, not a bad local file' do
        expect { expect(described_class.run).to eq(described_class::DOWNLOAD_FAILED) }
          .to output(include('DOWNLOAD FAILED')).to_stderr
      end
    end

    context 'when the local snapshot is not a snapshot' do
      let(:local_payload)  { '[]' }
      let(:router_payload) { payload }

      it 'blames the file on the branch' do
        expect { expect(described_class.run).to eq(described_class::DRIFT) }
          .to output(include('The problem is config/routing/gitlab_routes.json on this branch')).to_stderr
      end
    end

    context 'in a merged results pipeline' do
      let(:env) do
        {
          'CI_MERGE_REQUEST_PROJECT_PATH' => 'gitlab-org/gitlab',
          'CI_MERGE_REQUEST_TARGET_BRANCH_SHA' => 'target-sha',
          'CI_MERGE_REQUEST_DIFF_BASE_SHA' => 'merge-base-sha'
        }
      end

      let(:base_url) do
        'https://gitlab.com/api/v4/projects/gitlab-org%2Fgitlab' \
          '/repository/files/config%2Frouting%2Fgitlab_routes.json/raw?ref=target-sha'
      end

      it 'compares against the target branch SHA' do
        expect { described_class.run }.to output.to_stdout

        expect(a_request(:get, base_url)).to have_been_made
      end
    end

    context 'when CI_JOB_TOKEN is set' do
      let(:env) { { 'CI_JOB_TOKEN' => 'glcbt-test-token' } }

      it 'sends the JOB-TOKEN header with both download requests' do
        expect { described_class.run }.to output.to_stdout

        expect(a_request(:get, snapshot_url).with(headers: { 'JOB-TOKEN' => 'glcbt-test-token' }))
          .to have_been_made
        expect(a_request(:get, base_url).with(headers: { 'JOB-TOKEN' => 'glcbt-test-token' }))
          .to have_been_made
      end
    end

    context 'when CI_JOB_TOKEN is not set' do
      it 'omits the JOB-TOKEN header from both download requests' do
        expect { described_class.run }.to output.to_stdout

        expect(a_request(:get, snapshot_url).with { |request| request.headers.key?('Job-Token') })
          .not_to have_been_made
        expect(a_request(:get, base_url).with { |request| request.headers.key?('Job-Token') })
          .not_to have_been_made
      end
    end
  end
end
