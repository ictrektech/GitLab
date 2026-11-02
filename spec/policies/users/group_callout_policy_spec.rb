# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Users::GroupCalloutPolicy, feature_category: :shared do
  it { expect(described_class).to delegate_to(::UserPolicy) }
end
