# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Analytics::CycleAnalytics::ValueStreams::Update, feature_category: :value_stream_management do
  specify { expect(described_class).to require_graphql_authorizations(:update_value_stream) }
end
