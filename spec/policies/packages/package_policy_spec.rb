# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Packages::PackagePolicy, feature_category: :package_registry do
  let(:user) { build_stubbed(:user) }
  let(:package) { build_stubbed(:generic_package) }

  subject(:policy) { described_class.new(user, package) }

  it { is_expected.to delegate_to(Packages::Policies::ProjectPolicy) }
end
