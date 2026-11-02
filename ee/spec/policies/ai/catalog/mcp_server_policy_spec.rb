# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::McpServerPolicy, feature_category: :workflow_catalog do
  it { expect(described_class).to delegate_to(::Organizations::OrganizationPolicy) }
end
