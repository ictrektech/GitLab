# frozen_string_literal: true

require 'spec_helper'
require 'email_spec'

RSpec.describe Emails::Issues, feature_category: :team_planning do
  include EmailSpec::Matchers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, namespace: group) }
  let_it_be(:issue) { create(:issue, project: project) }

  context 'iterations' do
    let(:iterations_cadence) { build_stubbed(:iterations_cadence, title: "Plan cadence", group: group) }
    let(:iteration) do
      build_stubbed(:iteration, iterations_cadence: iterations_cadence, group: group,
        start_date: Date.new(2022, 9, 30), due_date: Date.new(2022, 10, 4))
    end

    describe '#changed_iteration_issue_email', :aggregate_failures do
      subject(:email) { Notify.changed_iteration_issue_email(user.id, issue.id, iteration, user.id) }

      it 'shows the iteration it was changed to' do
        expect(email).to have_body_text iteration.display_text
      end
    end

    describe '#removed_iteration_issue_email' do
      subject(:email) { Notify.removed_iteration_issue_email(user.id, issue.id, user.id) }

      it 'says iteration was removed' do
        expect(email).to have_body_text 'Iteration removed'
      end
    end
  end
end
