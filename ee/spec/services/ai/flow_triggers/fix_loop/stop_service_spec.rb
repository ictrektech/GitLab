# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::FixLoop::StopService, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:author) { create(:user) }
  let_it_be(:reviewer) { create(:user, :duo_code_review_bot, username: 'GitLabDuo') }
  let_it_be(:service_account) { create(:service_account, composite_identity_enforced: true, developer_of: project) }
  let_it_be_with_reload(:merge_request) do
    create(:merge_request, source_project: project, target_project: project, author: author)
  end

  let(:reason) { :max_fix_runs }
  let(:details) { { reviewer: reviewer, max_fix_runs: 3 } }

  subject(:execute) do
    described_class.new(merge_request, service_account: service_account, reason: reason, details: details).execute
  end

  def fix_loop_note
    merge_request.notes.user.authored_by(service_account).sole
  end

  shared_examples 'marks the merge request as a draft' do
    it 'marks the merge request as a draft as the service account', :aggregate_failures do
      execute

      expect(merge_request.reload).to be_draft
      expect(merge_request.notes.system.authored_by(service_account).pluck(:note))
        .to include('marked this merge request as **draft**')
    end
  end

  context 'when the loop reached max_fix_runs' do
    it_behaves_like 'marks the merge request as a draft'

    it 'tells the author why, without a mention of the reviewer', :aggregate_failures do
      expect(execute).to be_success

      expect(fix_loop_note.note).to eq(
        "@#{author.username} `GitLabDuo` requested changes after 3 fix runs, the limit of `max_fix_runs` in " \
          "`.gitlab-dap-factory.yml`. No fix run starts. This merge request is now a draft.\n\n" \
          "Read the review threads and decide the next step. When you mark the merge request as ready, " \
          "the next request for changes starts a new fix loop."
      )
    end

    context 'when the author is not a human' do
      before do
        merge_request.update!(author: create(:service_account))
      end

      it 'does not mention the author' do
        execute

        expect(fix_loop_note.note).to start_with('`GitLabDuo` requested changes after 3 fix runs')
      end
    end

    context 'with one fix run' do
      let(:details) { { reviewer: reviewer, max_fix_runs: 1 } }

      it 'names one fix run' do
        execute

        expect(fix_loop_note.note).to include('requested changes after 1 fix run, the limit')
      end
    end

    context 'when the merge request changed after the job loaded it' do
      before do
        MergeRequest.find(merge_request.id).update!(description: 'Changed by someone else')
      end

      it 'still marks the merge request as a draft' do
        execute

        expect(merge_request.reload).to be_draft
      end

      it 'reads the merge request again from the primary' do
        lb_session = ::Gitlab::Database::LoadBalancing::SessionMap.current(merge_request.load_balancer)
        allow(::Gitlab::Database::LoadBalancing::SessionMap).to receive(:current).and_return(lb_session)
        expect(lb_session).to receive(:use_primary).and_call_original

        execute
      end
    end

    context 'when the service account cannot update the merge request' do
      let(:service_account) { create(:service_account, composite_identity_enforced: true) }

      it 'changes nothing and logs the reason', :aggregate_failures do
        expect(Gitlab::AppJsonLogger).to receive(:warn).with(hash_including(
          'message' => 'Fix loop not stopped: the service account cannot update the merge request.',
          'merge_request_id' => merge_request.id,
          'reason' => :max_fix_runs
        ))

        expect(execute).to be_error
        expect(merge_request.reload).not_to be_draft
        expect(merge_request.notes.authored_by(service_account)).to be_empty
      end
    end

    context 'when the merge request is already a draft' do
      before do
        merge_request.update!(title: "Draft: #{merge_request.title}")
      end

      it 'only adds the note', :aggregate_failures do
        expect { execute }.not_to change { merge_request.notes.system.count }

        expect(fix_loop_note.note).to include('No fix run starts')
      end
    end

    context 'when the note is not created' do
      let(:note) { build(:note, noteable: merge_request, project: project) }

      before do
        note.errors.add(:base, 'Something went wrong')
        allow_next_instance_of(Notes::CreateService) do |service|
          allow(service).to receive(:execute).and_return(note)
        end
      end

      it 'still marks the merge request as a draft and logs the failure', :aggregate_failures do
        expect(Gitlab::AppJsonLogger).to receive(:warn).with(hash_including(
          'message' => 'Fix loop note not created.',
          'merge_request_id' => merge_request.id,
          'reason' => :max_fix_runs,
          'errors' => 'Something went wrong'
        ))

        expect(execute).to be_error
        expect(merge_request.reload).to be_draft
      end
    end

    context 'when the merge request is not marked as a draft' do
      before do
        allow_next_instance_of(MergeRequests::UpdateService) do |service|
          allow(service).to receive(:execute) { |mr| mr.errors.add(:title, 'is invalid') }
        end
      end

      it 'logs the failure and adds a note that does not claim a draft', :aggregate_failures do
        expect(Gitlab::AppJsonLogger).to receive(:warn).with(hash_including(
          'message' => 'Fix loop could not mark the merge request as a draft.',
          'errors' => 'Title is invalid'
        ))

        expect(execute).to be_success
        expect(fix_loop_note.note)
          .to include('No fix run starts. The fix loop could not mark this merge request as a draft.')
        expect(fix_loop_note.note).not_to include('now a draft')
      end
    end
  end

  context 'when the fix run did not start' do
    let(:reason) { :fix_run_not_started }
    let(:details) { {} }

    it_behaves_like 'marks the merge request as a draft'

    it 'tells the author' do
      execute

      expect(fix_loop_note.note).to eq(
        "@#{author.username} The fix run did not start, so the fix loop stops. " \
          "This merge request is now a draft.\n\n" \
          "Read the review threads and decide the next step. When you mark the merge request as ready, " \
          "the next request for changes starts a new fix loop."
      )
    end
  end

  context 'when the fix run ended without a push' do
    let(:reason) { :fix_run_without_push }
    let(:status) { :finished }
    let(:fix_run) { create(:duo_workflows_workflow, status, project: project) }
    let(:details) { { fix_run: fix_run } }
    let(:fix_run_link) do
      "(#{Gitlab.config.gitlab.url}/#{project.full_path}/-/automate/agent-sessions/#{fix_run.id})"
    end

    it_behaves_like 'marks the merge request as a draft'

    it 'tells the author, with a link to the fix run' do
      execute

      expect(fix_loop_note.note).to eq(
        "@#{author.username} [The fix run]#{fix_run_link} finished without a push, so no new review starts " \
          "and the fix loop stops. This merge request is now a draft.\n\n" \
          "Read the review threads and decide the next step. When you mark the merge request as ready, " \
          "the next request for changes starts a new fix loop."
      )
    end

    context 'when the fix run failed' do
      let(:status) { :failed }

      it 'tells the author that the fix run failed' do
        execute

        expect(fix_loop_note.note).to start_with(
          "@#{author.username} [The fix run]#{fix_run_link} failed before it pushed a fix, so no new review " \
            "starts and the fix loop stops. This merge request is now a draft."
        )
      end
    end

    context 'when a user stopped the fix run' do
      let(:status) { :stopped }

      it 'tells the author that a user stopped the fix run' do
        execute

        expect(fix_loop_note.note).to start_with(
          "@#{author.username} A user stopped [the fix run]#{fix_run_link} before it pushed a fix, so no new " \
            "review starts and the fix loop stops. This merge request is now a draft."
        )
      end
    end
  end

  context 'when the reviewer approved' do
    let(:reason) { :approved }
    let(:details) { { reviewer: reviewer, fix_runs: 2 } }

    it 'tells the author that the merge request is ready, and does not mark it as a draft', :aggregate_failures do
      expect(execute).to be_success

      expect(merge_request.reload).not_to be_draft
      expect(fix_loop_note.note).to eq(
        "@#{author.username} `GitLabDuo` approved this merge request after 2 fix runs. The fix loop ends, " \
          "and the merge request is ready for the final review."
      )
    end

    context 'with one fix run' do
      let(:details) { { reviewer: reviewer, fix_runs: 1 } }

      it 'names one fix run' do
        execute

        expect(fix_loop_note.note).to include('approved this merge request after 1 fix run. The fix loop ends')
      end
    end

    context 'without a fix run' do
      let(:details) { { reviewer: reviewer, fix_runs: 0 } }

      it 'tells the author that the merge request is ready, without a fix loop that ends' do
        execute

        expect(fix_loop_note.note).to eq(
          "@#{author.username} `GitLabDuo` approved this merge request without a fix run. The merge request is " \
            "ready for the final review."
        )
      end
    end

    context 'when the latest note of the service account already tells the author' do
      before do
        described_class.new(merge_request, service_account: service_account, reason: reason, details: details)
          .execute
      end

      it 'does not repeat the note' do
        expect { execute }.not_to change { merge_request.notes.count }
      end
    end
  end

  context 'when the configuration is not valid' do
    let(:reason) { :invalid_config }
    let(:details) { { errors: ['Unknown keys: `max_rounds`.', '`label` must be a string.'] } }

    it 'tells the author the errors, and does not mark the merge request as a draft', :aggregate_failures do
      execute

      expect(merge_request.reload).not_to be_draft
      expect(fix_loop_note.note).to eq(
        "@#{author.username} No fix run starts, because the `review` key in `.gitlab-dap-factory.yml` " \
          "is not valid:\n\n- Unknown keys: `max_rounds`.\n- `label` must be a string."
      )
    end

    context 'when the latest note of the service account already tells the author' do
      before do
        described_class.new(merge_request, service_account: service_account, reason: reason, details: details)
          .execute
      end

      it 'does not repeat the note' do
        expect { execute }.not_to change { merge_request.notes.count }
      end

      context 'when the service account posted another note after it' do
        before do
          create(:note, noteable: merge_request, project: project, author: service_account, note: 'Another note')
        end

        it 'tells the author again' do
          expect { execute }.to change { merge_request.notes.count }.by(1)
        end
      end
    end
  end

  context 'with an unknown reason' do
    let(:reason) { :something_else }

    it 'raises an error' do
      expect { execute }.to raise_error(ArgumentError, 'Unknown reason: :something_else')
    end
  end
end
