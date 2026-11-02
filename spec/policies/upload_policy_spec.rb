# frozen_string_literal: true

require 'spec_helper'

RSpec.describe UploadPolicy do
  let(:user) { build_stubbed(:user) }
  let(:upload) { build_stubbed(:upload, model: model) }

  subject(:policy) { described_class.new(user, upload) }

  context 'with project upload' do
    let(:model) { build_stubbed(:project) }

    it { is_expected.to delegate_to(ProjectPolicy) }
  end

  context 'with group upload' do
    let(:model) { build_stubbed(:group) }

    it { is_expected.to delegate_to(GroupPolicy) }
  end

  context 'with upload associated with other model' do
    let(:model) { build_stubbed(:user) }

    it { is_expected.to delegate_to(UserPolicy) }
  end
end
