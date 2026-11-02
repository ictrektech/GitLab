# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanPolicy, feature_category: :vulnerability_management do
  it { expect(described_class.new(build_stubbed(:user), build_stubbed(:security_scan))).to delegate_to(ProjectPolicy) }

  describe 'read_scan' do
    let_it_be(:user) { create(:user) }
    let_it_be(:scan) { create(:security_scan) }
    let_it_be(:project) { scan.project }

    subject { described_class.new(user, scan) }

    context 'when the security_dashboard feature is enabled' do
      before do
        stub_licensed_features(security_dashboard: true)
      end

      context "when the current user has developer access to the scan's project" do
        before_all do
          project.add_developer(user)
        end

        it { is_expected.to be_allowed(:read_scan) }
      end

      context "when the current user does not have developer access to the scan's project" do
        it { is_expected.to be_disallowed(:read_scan) }
      end
    end

    context 'when the security_dashboard feature is disabled' do
      before_all do
        project.add_developer(user)
      end

      before do
        stub_licensed_features(security_dashboard: false)
      end

      it { is_expected.to be_disallowed(:read_scan) }
    end
  end
end
