# frozen_string_literal: true

# Requires `oversized_params`: params that make the definition larger than the size limit.
RSpec.shared_examples 'rejects an oversized definition before validation' do
  let(:params) { super().merge(oversized_params) }

  it_behaves_like 'an error response', ['Definition is too large. Maximum size is 80 KiB']

  it 'does not call DWS' do
    expect(Ai::DuoWorkflow::DuoWorkflowService::Client).not_to receive(:new)

    execute_service
  end
end

# Requires `oversized_definition`: a YAML string larger than the size limit.
RSpec.shared_examples 'rejects an oversized YAML definition before validation' do
  let(:params) { super().merge(definition: oversized_definition) }

  it_behaves_like 'an error response', ['YAML is too large. Maximum size is 40 KiB']

  it 'does not parse the definition' do
    allow(YAML).to receive(:safe_load).and_call_original

    execute_service

    expect(YAML).not_to have_received(:safe_load).with(oversized_definition)
  end
end
