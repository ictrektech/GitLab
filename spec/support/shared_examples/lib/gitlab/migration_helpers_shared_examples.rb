# frozen_string_literal: true

RSpec.shared_examples 'skips validation' do |validation_option|
  it 'skips validation' do
    expect(model).not_to receive(:disable_statement_timeout)
    expect(model).to receive(:execute).with(/LOCK TABLE/)
    expect(model).to receive(:execute).with(/ADD CONSTRAINT/)
    expect(model).not_to receive(:execute).with(/VALIDATE CONSTRAINT/)

    model.add_concurrent_foreign_key(*args, **options.merge(validation_option))
  end
end

RSpec.shared_examples 'performs validation' do |validation_option|
  it 'performs validation' do
    expect(model).to receive(:disable_statement_timeout).and_yield
    expect(model).to receive(:execute).with(/LOCK TABLE/)
    expect(model).to receive(:execute).ordered.with(/NOT VALID/)
    expect(model).to receive(:execute).ordered.with(/VALIDATE CONSTRAINT/)

    model.add_concurrent_foreign_key(*args, **options.merge(validation_option))
  end
end
