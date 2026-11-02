# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['AiMessageRole'], feature_category: :chat_engine do
  let(:expected_values) { %w[USER ASSISTANT SYSTEM] }

  subject { described_class.values.keys }

  it { is_expected.to match_array(expected_values) }
end
