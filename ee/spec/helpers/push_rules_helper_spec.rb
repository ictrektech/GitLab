# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PushRulesHelper, feature_category: :source_code_management do
  let_it_be(:project) { create(:project) }
  let_it_be_with_reload(:global_push_rule) { create(:organization_push_rule, organization_id: project.organization.id) }
  let_it_be_with_reload(:push_rule) { create(:push_rule, project: project) }

  let(:possible_help_texts) do
    {
      commit_committer_check_base_help: /Users can only push commits to this repository if the committer email is one of their own verified emails/,
      reject_unsigned_commits_base_help: /Only signed commits can be pushed to this repository/,
      reject_non_dco_commits_base_help: %r{Only commits that include a <code>Signed-off-by:</code> element can be pushed to this repository},
      default_admin_help: /This setting will be applied to all projects unless overridden for a project/,
      setting_instance_on: /This setting is on for the instance/
    }
  end

  shared_examples 'validates push rule help text' do
    where(:global_setting, :enabled_globally, :enabled_in_project, :help_text, :invalid_text) do
      [
        [true, true, false, :default_admin_help, nil],
        [true, false, false, :default_admin_help, nil],
        [true, true, true, :default_admin_help, nil],
        [true, false, true, :default_admin_help, nil],
        [false, true, nil, :setting_instance_on, nil],
        [false, true, false, :setting_instance_on, nil],
        [false, true, true, :setting_instance_on, nil],
        [false, false, nil, :base_help, :setting_instance_on],
        [false, false, false, :base_help, :setting_instance_on],
        [false, false, true, :base_help, :setting_instance_on]
      ]
    end

    with_them do
      %i[reject_unsigned_commits commit_committer_check reject_non_dco_commits].each do |rule_attr|
        context "when `#{rule_attr}`" do
          before do
            global_push_rule.update_column(rule_attr, enabled_globally)
            push_rule.update_column(rule_attr, enabled_in_project)
          end

          it "has the correct help text" do
            rule = global_setting ? global_push_rule : push_rule
            message = possible_help_texts[:"#{rule_attr}_#{help_text}"].presence || possible_help_texts[help_text]

            expect(helper.public_send("#{rule_attr}_description", rule)).to match(message)

            if invalid_text
              expect(helper.public_send("#{rule_attr}_description", rule)).not_to match(possible_help_texts[invalid_text])
            end
          end
        end
      end
    end
  end

  it_behaves_like 'validates push rule help text'

  describe '#commit_committer_name_check_description' do
    it 'returns the right description' do
      expect(
        helper.commit_committer_name_check_description(push_rule)
      ).to eq(s_("ProjectSettings|Users can only push commits to this repository " \
        "if the commit author name is consistent with their GitLab account name."))
    end
  end
end
