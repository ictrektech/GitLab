# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:ai_catalog tasks', :silence_stdout, feature_category: :ai_catalog_curation do
  before do
    Rake.application.rake_require 'tasks/gitlab/ai_catalog'
  end

  describe 'ai_catalog:seed_external_agents' do
    subject(:run_task) { run_rake_task 'gitlab:ai_catalog:seed_external_agents' }

    it 'calls Gitlab::Ai::Catalog::ThirdPartyFlows::Seeder.run!' do
      expect(Gitlab::Ai::Catalog::ThirdPartyFlows::Seeder).to receive(:run!)

      run_task
    end
  end

  describe 'ai_catalog:publish_skills' do
    # `let` rather than `let_it_be`, as the testing guide asks of rake task specs.
    let(:project) { create(:project) }
    let(:response) { ServiceResponse.success(payload: payload) }
    let(:payload) do
      {
        created: ['skills/alpha/SKILL.md'],
        updated: [], deleted: [], unchanged: [], failed: [],
        unpublishable: [{ path: 'skills/beta/SKILL.md', errors: ['name is required.'] }]
      }
    end

    subject(:run_task) { run_rake_task('gitlab:ai_catalog:publish_skills', project.full_path) }

    before do
      allow(::Ai::Catalog::Skills::PublishService).to receive(:new).with(project: project)
        .and_return(instance_double(::Ai::Catalog::Skills::PublishService, execute: response))
    end

    it 'prints every bucket with its count, its paths and their reasons' do
      expect { run_task }.to output(
        a_string_including(
          'created', 'skills/alpha/SKILL.md', 'unpublishable', 'skills/beta/SKILL.md', 'name is required.'
        )
      ).to_stdout
    end

    context 'when no project path is given' do
      subject(:run_task) { run_rake_task('gitlab:ai_catalog:publish_skills') }

      it 'aborts with the usage line' do
        expect { run_task }.to raise_error(SystemExit, /Usage:/)
      end
    end

    context 'when the project does not exist' do
      subject(:run_task) { run_rake_task('gitlab:ai_catalog:publish_skills', 'no/such-project') }

      it 'aborts' do
        expect { run_task }.to raise_error(SystemExit, /Project not found/)
      end
    end

    context 'when the publish fails' do
      let(:response) { ServiceResponse.error(message: 'Could not read skills', reason: :scan_failed) }

      it 'exits non-zero so a caller can tell' do
        expect { run_task }
          .to raise_error(an_instance_of(SystemExit).and(having_attributes(status: 1)))
      end
    end
  end
end
