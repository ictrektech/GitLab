# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::ByteLimitedIo, feature_category: :mcp_server do
  let(:io) { StringIO.new('a' * 10) }

  subject(:limited_io) { described_class.new(io, max_bytes: 6) }

  it 'passes reads through up to the limit', :aggregate_failures do
    expect(limited_io.read(4)).to eq('aaaa')
    expect(limited_io.read(2)).to eq('aa')
  end

  it 'raises once more than the limit has been read' do
    limited_io.read(4)

    expect { limited_io.read(3) }.to raise_error(described_class::LimitExceeded)
  end

  it 'counts a read without a length' do
    expect { limited_io.read }.to raise_error(described_class::LimitExceeded)
  end

  it 'stops counting once the limit is removed' do
    limited_io.read(6)
    limited_io.remove_limit!

    expect(limited_io.read).to eq('aaaa')
  end

  it 'delegates everything else' do
    limited_io.seek(8)

    expect(limited_io.tell).to eq(8)
  end
end
