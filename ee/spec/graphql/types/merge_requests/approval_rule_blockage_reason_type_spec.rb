# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['ApprovalRuleBlockageReason'], feature_category: :code_testing do
  let(:fields) { %i[reason coverage threshold base_coverage] }

  it { expect(described_class).to have_graphql_fields(fields) }
end
