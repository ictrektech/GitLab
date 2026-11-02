# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Analytics::CycleAnalytics::ValueStreams::Destroy, feature_category: :value_stream_management do
  specify { expect(described_class).to require_graphql_authorizations(:delete_value_stream) }
end
