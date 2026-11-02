# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Streaming::Destinations, feature_category: :audit_events do
  describe '.for_category' do
    using RSpec::Parameterized::TableSyntax

    where(:category, :stream_destination_class) do
      'aws'  | AuditEvents::Streaming::Destinations::AmazonS3StreamDestination
      'gcp'  | AuditEvents::Streaming::Destinations::GoogleCloudLoggingStreamDestination
      'http' | AuditEvents::Streaming::Destinations::HttpStreamDestination
    end

    with_them do
      it 'returns the stream destination class for the category' do
        expect(described_class.for_category(category)).to eq(stream_destination_class)
      end
    end

    it 'raises ArgumentError for an unknown category' do
      expect { described_class.for_category('invalid') }
        .to raise_error(ArgumentError, 'Stream destination class for category not found: invalid')
    end
  end
end
