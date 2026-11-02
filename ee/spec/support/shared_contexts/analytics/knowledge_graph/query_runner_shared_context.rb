# frozen_string_literal: true

RSpec.shared_context 'with a stubbed Orbit query runner' do
  let(:orbit_runner_response) { Analytics::KnowledgeGraph::QueryRunner::Response.json('{"result":[]}') }
  let(:orbit_query_params) { [] }

  before do
    allow(Analytics::KnowledgeGraph::QueryRunner).to receive(:new) do |params, **|
      orbit_query_params << params
      instance_double(Analytics::KnowledgeGraph::QueryRunner, execute: orbit_runner_response)
    end
  end
end
