# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:seed:workplans', :silence_stdout, feature_category: :duo_agent_platform do
  let(:project) { create(:project) }
  let(:user) { create(:user, maintainer_of: project) }
  let(:seeder) { instance_double(Gitlab::Seeders::WorkItems::Workplans, seed!: []) }

  before do
    Rake.application.rake_require 'tasks/gitlab/seed/workplans'
  end

  it 'seeds the project as the user' do
    expect(Gitlab::Seeders::WorkItems::Workplans).to receive(:new)
      .with(project: project, user: user, reset: false).and_return(seeder)

    run_rake_task('gitlab:seed:workplans', project.full_path, user.username)
  end

  it 'prints where workplan content is stored' do
    allow(Gitlab::Seeders::WorkItems::Workplans).to receive(:new).and_return(seeder)

    expect { run_rake_task('gitlab:seed:workplans', project.full_path, user.username) }
      .to output(a_string_including("Workplan content stored in #{WorkItems::AgentPlanContentUploader.root}"))
      .to_stdout
  end

  it 'skips the storage path when object storage is enabled' do
    allow(Gitlab::Seeders::WorkItems::Workplans).to receive(:new).and_return(seeder)
    allow(WorkItems::AgentPlanContentUploader).to receive(:object_store_enabled?).and_return(true)

    expect { run_rake_task('gitlab:seed:workplans', project.full_path, user.username) }
      .not_to output(/Workplan content stored in/).to_stdout
  end

  it 'prints whether each work item was created or already existed' do
    created, existing = create_list(:work_item, 2, project: project)
    allow(seeder).to receive(:seed!).and_return([
      { work_item: created, created: true },
      { work_item: existing, created: false }
    ])
    allow(Gitlab::Seeders::WorkItems::Workplans).to receive(:new).and_return(seeder)

    expect { run_rake_task('gitlab:seed:workplans', project.full_path, user.username) }
      .to output(
        a_string_including(
          "created #{Gitlab::UrlBuilder.build(created)}  #{created.title}",
          "exists  #{Gitlab::UrlBuilder.build(existing)}  #{existing.title}"
        )
      ).to_stdout
  end

  it 'passes RESET through' do
    stub_env('RESET', '1')

    expect(Gitlab::Seeders::WorkItems::Workplans).to receive(:new)
      .with(project: project, user: user, reset: true).and_return(seeder)

    run_rake_task('gitlab:seed:workplans', project.full_path, user.username)
  end

  it 'aborts without arguments' do
    expect { run_rake_task('gitlab:seed:workplans') }.to raise_error(SystemExit).and output(/Usage/).to_stderr
  end

  it 'aborts when the project does not exist' do
    expect { run_rake_task('gitlab:seed:workplans', 'missing/project', user.username) }
      .to raise_error(SystemExit).and output(/Project not found/).to_stderr
  end

  it 'aborts when the user does not exist' do
    expect { run_rake_task('gitlab:seed:workplans', project.full_path, 'missing-user') }
      .to raise_error(SystemExit).and output(/User not found/).to_stderr
  end

  it 'aborts outside development and test' do
    allow(Gitlab).to receive(:dev_or_test_env?).and_return(false)

    expect { run_rake_task('gitlab:seed:workplans', project.full_path, user.username) }
      .to raise_error(SystemExit).and output(/only run in development or test/).to_stderr
  end
end
