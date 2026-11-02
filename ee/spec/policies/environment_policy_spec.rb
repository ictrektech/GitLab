# frozen_string_literal: true
require 'spec_helper'

RSpec.describe EnvironmentPolicy do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }

  let_it_be_with_refind(:user) { create(:user) }
  let_it_be_with_refind(:environment) do
    # The review app deployment needs the branch to exist.
    project.repository.add_branch(user, 'development', project.commit.id)
    create(:environment, :with_review_app, ref: 'development', project: project)
  end

  describe '#stop_environment' do
    subject { user.can?(:stop_environment, environment) }

    it_behaves_like 'protected environments access'
  end

  describe '#destroy_environment' do
    subject { user.can?(:destroy_environment, environment) }

    before do
      environment.stop_complete!
    end

    it_behaves_like 'protected environments access'
  end

  describe '#create_environment_terminal' do
    subject { user.can?(:create_environment_terminal, environment) }

    it_behaves_like 'protected environments access', developer_access: false
  end
end
