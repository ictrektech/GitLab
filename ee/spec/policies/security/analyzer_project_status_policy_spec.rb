# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::AnalyzerProjectStatusPolicy, feature_category: :security_asset_inventories do
  it { expect(described_class).to delegate_to(ProjectPolicy) }
end
