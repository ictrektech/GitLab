# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::ScannerPolicy, feature_category: :vulnerability_management do
  describe 'read_vulnerability_scanner' do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, developer_of: project) }
    let_it_be(:vulnerability_scanner) { create(:vulnerabilities_scanner, project: project) }

    subject { described_class.new(user, vulnerability_scanner) }

    it { is_expected.to delegate_to(ProjectPolicy) }

    context 'when the security_dashboard feature is disabled' do
      before do
        stub_licensed_features(security_dashboard: false)
      end

      it { is_expected.to be_disallowed(:read_vulnerability_scanner) }
    end
  end
end
