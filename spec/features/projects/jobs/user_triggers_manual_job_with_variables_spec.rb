# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User triggers manual job with variables', :js, feature_category: :continuous_integration do
  let(:user) { create(:user) }
  let(:project) { create(:project, :repository, namespace: user.namespace) }
  let(:pipeline) { create(:ci_pipeline, project: project, sha: project.commit.sha, ref: 'master') }
  let!(:build) { create(:ci_build, :manual, pipeline: pipeline) }

  before do
    project.update!(ci_pipeline_variables_minimum_override_role: :maintainer)
    project.add_maintainer(user)
    project.enable_ci

    sign_in(user)

    visit(project_job_path(project, build))
  end

  # Regression test for https://gitlab.com/gitlab-org/gitlab/-/issues/601317.
  #
  # Feature specs run with the vue3_migrate_jobs flag enabled by default, so this
  # exercises the Vue 3 compat build. Adding a variable flips the last row's
  # `canRemove(index)` from false to true, switching its delete button between the
  # v-else placeholder and the v-if branch that carries `v-gl-tooltip`. When those
  # same-tag branches lack distinct keys, @vue/compat patches one onto the other in
  # place and throws in `invokeDirectiveHook` ("Cannot read properties of undefined
  # (reading 'value')") because the new vnode has more directives than the old one.
  # The crash aborts the component update, so no further rows are ever committed.
  #
  # The real fix injects keys on same-tag v-if/v-else branches for the
  # `?vue3`-infected build (config/webpack.config.js wiring config/vue3migration/compilers/vue2_template.js). This
  # only reproduces with the real webpack-compiled Vue 3 compat build in a browser;
  # jsdom/jest uses @vue/compiler-dom and does not exercise this codepath, so the
  # regression must be guarded here, at the feature level.
  it 'allows adding more than one variable', :aggregate_failures do
    click_button 'Variables'

    expect(page).to have_selector('[data-testid="ci-variable-row"]', count: 1)

    enter_key_in_last_row('key_one')
    expect(page).to have_selector('[data-testid="ci-variable-row"]', count: 2)

    enter_key_in_last_row('key_two')
    expect(page).to have_selector('[data-testid="ci-variable-row"]', count: 3)
  end

  # Entering a key in the last row fires its `change` handler (`addEmptyVariable`),
  # which pushes the next empty row.
  def enter_key_in_last_row(key)
    # The preceding count assertion guarantees the rows exist, so `all(...).last` is
    # safe here. A `:last-child` selector would not work: help-text divs follow the
    # rows inside the collapse, so no `ci-variable-row` is ever the last child.
    row = all('[data-testid="ci-variable-row"]').last
    within(row) do
      field = find_by_testid('ci-variable-key')
      field.set(key)
      field.send_keys(:tab) # blur to fire the `change` handler
    end
  end
end
