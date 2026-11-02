# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::CodeReview::Definition, feature_category: :dap_code_review do
  subject(:flow) { Ai::Catalog::FoundationalFlow.code_review_v1 }

  let_it_be(:project) { create(:project) }

  def code_review_context(surface)
    [{ 'Category' => 'code_review_context', 'Content' => Gitlab::Json.dump(surface: surface) }]
  end

  describe '.code_review_v1' do
    it 'returns the code review foundational flow' do
      expect(flow.foundational_flow_reference).to eq('code_review/v1')
      expect(flow.display_name).to eq('Code Review')
      expect(flow.ai_feature).to eq('review_merge_request_dap')
      expect(flow.feature_maturity).to eq('ga')
    end
  end

  describe '#resolve_ai_feature' do
    let_it_be(:user) { create(:user) }

    let(:additional_context) { nil }

    subject(:ai_feature) { flow.resolve_ai_feature(current_user: user, additional_context: additional_context) }

    context 'when duo_code_review_deep_flow is enabled for the user' do
      before do
        stub_feature_flags(duo_code_review_deep_flow: user)
      end

      it { is_expected.to eq('review_merge_request_dap_deep') }

      context 'when a standard review is requested' do
        let(:additional_context) do
          [{ 'Category' => 'code_review_context', 'Content' => Gitlab::Json.dump(depth: 'standard') }]
        end

        it { is_expected.to eq('review_merge_request_dap') }
      end

      context 'when a deep review is requested' do
        let(:additional_context) do
          [{ 'Category' => 'code_review_context', 'Content' => Gitlab::Json.dump(depth: 'deep') }]
        end

        it { is_expected.to eq('review_merge_request_dap_deep') }
      end
    end

    context 'when duo_code_review_deep_flow is disabled' do
      before do
        stub_feature_flags(duo_code_review_deep_flow: false)
      end

      it { is_expected.to eq('review_merge_request_dap') }
    end
  end

  describe '#resolve_noteable_for' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    it 'returns the merge request matching the iid goal' do
      expect(flow.resolve_noteable_for(project: project, goal: merge_request.iid)).to eq(merge_request)
    end

    it 'returns nil when no merge request matches the goal' do
      expect(flow.resolve_noteable_for(project: project, goal: non_existing_record_iid)).to be_nil
    end
  end

  describe '#validate_start_request' do
    subject(:result) { flow.validate_start_request(container: project, goal: goal) }

    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    let(:goal) { merge_request.iid.to_s }

    it 'returns a success with the normalized goal for an IID goal' do
      expect(result).to be_success
      expect(result.payload[:goal]).to eq(merge_request.iid.to_s)
    end

    context 'with a merge request URL goal' do
      let(:goal) do
        url = Gitlab::Routing.url_helpers.project_merge_request_url(project, merge_request)
        "#{url}/diffs#note_123"
      end

      it 'normalizes the goal to the IID' do
        expect(result).to be_success
        expect(result.payload[:goal]).to eq(merge_request.iid.to_s)
      end
    end

    context 'when the goal is not a merge request identifier' do
      let(:goal) { 'Review my merge request' }

      it 'returns an error', :aggregate_failures do
        expect(result).to be_error
        expect(result.message).to include('must be a merge request IID')
        expect(result.reason).to eq(:invalid_goal)
      end
    end

    context 'when no merge request matches the IID' do
      let(:goal) { non_existing_record_iid.to_s }

      it 'returns an error' do
        expect(result).to be_error
      end
    end

    context 'when the container is not a project' do
      subject(:result) { flow.validate_start_request(container: build(:group), goal: merge_request.iid.to_s) }

      it 'returns an error', :aggregate_failures do
        expect(result).to be_error
        expect(result.message).to include('require a project context')
        expect(result.reason).to eq(:invalid_goal)
      end
    end

    context 'when code_review_context declares the merge_request surface' do
      subject(:result) do
        flow.validate_start_request(
          container: project, goal: goal, additional_context: code_review_context('merge_request')
        )
      end

      it 'applies the merge request rule' do
        expect(result).to be_success
        expect(result.payload[:goal]).to eq(merge_request.iid.to_s)
      end
    end

    context 'when code_review_context declares the checkout surface' do
      subject(:result) do
        flow.validate_start_request(
          container: container,
          goal: goal,
          additional_context: code_review_context('checkout'),
          client_executed: client_executed
        )
      end

      let(:container) { project }
      let(:goal) { 'the working tree' }
      let(:client_executed) { true }

      context 'when the client does not execute the run' do
        let(:client_executed) { false }

        it 'returns an error', :aggregate_failures do
          expect(result).to be_error
          expect(result.message).to include('cannot be started on the server')
          expect(result.reason).to eq(:invalid_goal)
        end
      end

      it 'accepts a free text goal as given', :aggregate_failures do
        expect(result).to be_success
        expect(result.payload[:goal]).to eq('the working tree')
      end

      context 'when the goal has surrounding whitespace' do
        let(:goal) { "  the working tree\n" }

        it 'strips it' do
          expect(result.payload[:goal]).to eq('the working tree')
        end
      end

      context 'when the container is not a project' do
        let(:container) { build(:group) }

        it 'still succeeds' do
          expect(result).to be_success
        end
      end

      context 'when the goal is blank' do
        let(:goal) { "  \n" }

        it 'returns an error', :aggregate_failures do
          expect(result).to be_error
          expect(result.message).to include('must describe what to review')
          expect(result.reason).to eq(:invalid_goal)
        end
      end

      context 'when the goal is nil' do
        let(:goal) { nil }

        it 'returns an error' do
          expect(result).to be_error
        end
      end
    end

    context 'when code_review_context declares an unknown surface' do
      subject(:result) do
        flow.validate_start_request(container: project, goal: goal, additional_context: code_review_context('branch'))
      end

      it 'returns an error', :aggregate_failures do
        expect(result).to be_error
        expect(result.message).to include('code_review_context.surface must be one of merge_request, checkout')
        expect(result.reason).to eq(:invalid_additional_context)
      end
    end

    context 'when code_review_context content is JSON but not an object' do
      subject(:result) do
        flow.validate_start_request(
          container: project,
          goal: 'Review my merge request',
          additional_context: [{ 'Category' => 'code_review_context', 'Content' => '["checkout"]' }]
        )
      end

      it 'applies the merge request rule' do
        expect(result).to be_error
        expect(result.message).to include('must be a merge request IID')
      end
    end

    context 'when code_review_context has no surface key' do
      subject(:result) do
        flow.validate_start_request(
          container: project,
          goal: merge_request.iid.to_s,
          additional_context: [{ 'Category' => 'code_review_context', 'Content' => '{"other":"value"}' }]
        )
      end

      it 'applies the merge request rule' do
        expect(result).to be_success
        expect(result.payload[:goal]).to eq(merge_request.iid.to_s)
      end
    end

    context 'when code_review_context content is not a JSON object' do
      subject(:result) do
        flow.validate_start_request(
          container: project,
          goal: 'Review my merge request',
          additional_context: [{ 'Category' => 'code_review_context', 'Content' => 'not json' }]
        )
      end

      it 'applies the merge request rule' do
        expect(result).to be_error
        expect(result.message).to include('must be a merge request IID')
      end
    end

    context 'when the resolver returns something other than a ServiceResponse' do
      let(:goal) { '1' }

      it 'raises an ArgumentError' do
        allow(flow).to receive(:start_request_validator).and_return(->(**) { true })

        expect { result }.to raise_error(ArgumentError, /must return a ServiceResponse or nil, got TrueClass/)
      end
    end
  end

  it 'resolves additional context with the Context module' do
    expect(flow.additional_context_resolver).to eq(Ai::Catalog::FoundationalFlow::CodeReview::Context)
  end

  it 'also sends the context under code_review_context while flow configs migrate' do
    expect(flow.context_category_alias).to eq('code_review_context')
  end
end
