# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Types::WorkItems::Widgets::SeverityInputType, feature_category: :incident_management do
  it { expect(described_class.graphql_name).to eq('WorkItemWidgetSeverityInput') }

  it { expect(described_class.arguments.keys).to contain_exactly('severity') }
end
