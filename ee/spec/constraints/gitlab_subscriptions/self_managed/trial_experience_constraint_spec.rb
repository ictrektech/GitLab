# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::SelfManaged::TrialExperienceConstraint, feature_category: :acquisition do
  describe '#matches?' do
    subject(:matches) { described_class.new.matches?(instance_double(ActionDispatch::Request)) }

    before do
      allow(::Gitlab::Dedicated).to receive(:feature_available?)
        .with(:skip_ultimate_trial_experience).and_return(dedicated)
    end

    context 'when the instance is Dedicated' do
      let(:dedicated) { true }

      it { is_expected.to be(false) }
    end

    context 'when the instance is not Dedicated' do
      let(:dedicated) { false }

      it { is_expected.to be(true) }
    end
  end
end
