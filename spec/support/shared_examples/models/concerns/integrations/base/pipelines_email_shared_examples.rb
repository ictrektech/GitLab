# frozen_string_literal: true

RSpec.shared_examples Integrations::Base::PipelinesEmail do
  let(:pipeline) do
    create(:ci_pipeline, :failed,
      project: project,
      sha: project.commit('master').sha,
      ref: project.default_branch
    )
  end

  let_it_be_with_reload(:project) { create(:project, :repository) }

  let(:recipients) { 'test@gitlab.com' }
  let(:receivers) { [recipients] }

  let(:data) do
    Gitlab::DataBuilder::Pipeline.build(pipeline)
  end

  describe '#initialize_properties' do
    using RSpec::Parameterized::TableSyntax

    where(:legacy_default_only, :selection, :expected_selection) do
      true  | nil         | 'default'
      false | nil         | 'all'
      true  | 'protected' | 'protected'
      false | 'protected' | 'protected'
    end

    with_them do
      it 'migrates the legacy setting without overriding an explicit branch selection' do
        properties = { notify_only_default_branch: legacy_default_only, branches_to_be_notified: selection }.compact
        integration = described_class.new(project: project, properties: properties)

        expect(integration.branches_to_be_notified).to eq(expected_selection)
      end
    end
  end

  describe 'Validations' do
    describe 'branch selection', :aggregate_failures do
      subject(:integration) { described_class.new(project: project, recipients: recipients, active: true) }

      using RSpec::Parameterized::TableSyntax

      where(:selection, :valid) do
        'all'                   | true
        'default'               | true
        'protected'             | true
        'default_and_protected' | true
        ' default '             | true
        'other'                 | false
        'default,protected'     | false
        'default, protected'    | false
        'bogus'                 | false
        ''                      | false
        nil                     | false
      end

      with_them do
        it 'accepts only the existing branch choices' do
          integration.branches_to_be_notified = selection

          expect(integration.valid?).to be(valid)
        end
      end

      it 'defaults an omitted selection when other properties are supplied' do
        expect(integration.branches_to_be_notified).to eq('default')
        expect(integration).to be_valid
      end

      it 'rejects an explicitly empty selection on initialization' do
        integration = described_class.new(project: project, recipients: recipients, active: true,
          branches_to_be_notified: nil)

        expect(integration).not_to be_valid
        expect(integration.errors[:branches_to_be_notified]).not_to be_empty
      end

      it 'normalizes surrounding whitespace before saving' do
        integration.branches_to_be_notified = ' default_and_protected '
        integration.save!

        expect(integration.reload.branches_to_be_notified).to eq('default_and_protected')
      end

      context 'with an existing integration' do
        let(:existing_integration) { described_class.find(integration.id) }

        before do
          integration.branches_to_be_notified = ' legacy '
          integration.save!(validate: false)
        end

        it 'allows unrelated changes with an unchanged legacy selection' do
          expect(existing_integration.update(recipients: 'updated@example.com')).to be(true)
          expect(existing_integration.reload.branches_to_be_notified).to eq(' legacy ')
        end

        it 'rejects a change to another invalid selection' do
          expect(existing_integration.update(branches_to_be_notified: 'invalid')).to be(false)
          expect(existing_integration.errors[:branches_to_be_notified]).not_to be_empty
        end

        it 'allows a change to a valid selection' do
          expect(existing_integration.update(branches_to_be_notified: 'protected')).to be(true)
          expect(existing_integration.reload.branches_to_be_notified).to eq('protected')
        end
      end

      it 'allows an inactive integration without a branch selection' do
        integration.active = false
        integration.branches_to_be_notified = nil

        expect(integration).to be_valid
      end
    end

    context 'when integration is active' do
      before do
        subject.active = true
      end

      it { is_expected.to validate_presence_of(:recipients) }
    end

    context 'when integration is inactive' do
      before do
        subject.active = false
      end

      it { is_expected.not_to validate_presence_of(:recipients) }
    end

    describe 'validates number of recipients' do
      before do
        stub_const("Integrations::Base::PipelinesEmail::RECIPIENTS_LIMIT", 2)
      end

      subject(:integration) do
        integration = described_class.new(recipients: recipients, active: true)
        integration.project = project unless integration.instance?
        integration
      end

      context 'with valid number of recipients' do
        let(:recipients) { 'foo@bar.com, , ' }

        it 'does not count empty emails' do
          is_expected.to be_valid
        end
      end

      context 'with invalid number of recipients' do
        let(:recipients) { 'foo@bar.com bar@foo.com bob@gitlab.com' }

        it { is_expected.not_to be_valid }

        it 'adds an error message' do
          integration.valid?

          expect(integration.errors).to contain_exactly('Recipients can\'t exceed 2')
        end

        context 'when integration is not active' do
          before do
            integration.active = false
          end

          it { is_expected.to be_valid }
        end
      end
    end
  end

  shared_examples 'sending email' do |branches_to_be_notified: nil|
    before do
      subject.recipients = recipients
      subject.branches_to_be_notified = branches_to_be_notified if branches_to_be_notified

      perform_enqueued_jobs do
        run
      end
    end

    # rubocop:disable RSpec/NoExpectationExample -- expectation is present
    it 'sends email' do
      emails = receivers.map do |r|
        double(notification_email_or_default: r, username: r, id: r) # rubocop:disable RSpec/VerifiedDoubles -- legacy use
      end

      should_only_email(*emails)
    end
    # rubocop:enable RSpec/NoExpectationExample
  end

  shared_examples 'not sending email' do |branches_to_be_notified: nil|
    before do
      subject.recipients = recipients
      subject.branches_to_be_notified = branches_to_be_notified if branches_to_be_notified

      perform_enqueued_jobs do
        run
      end
    end

    # rubocop:disable RSpec/NoExpectationExample -- expectation is present
    it 'does not send email' do
      should_not_email_anyone
    end
    # rubocop:enable RSpec/NoExpectationExample
  end

  # aliases for pipeline notification integration shared examples
  shared_examples 'triggered PipelinesEmail integration' do
    it_behaves_like 'sending email'
  end

  shared_examples 'untriggered PipelinesEmail integration' do
    it_behaves_like 'not sending email'
  end

  describe '#should_enqueue?' do
    subject(:should_enqueue) { integration.should_enqueue?(data.with_indifferent_access) }

    let(:integration) do
      described_class.new(project: project, recipients: recipients, active: true,
        notify_only_broken_pipelines: notify_only_broken_pipelines)
    end

    let(:notify_only_broken_pipelines) { false }

    context 'with a failed pipeline' do
      it { is_expected.to be(true) }

      context 'when the branch would not be notified' do
        before do
          integration.branches_to_be_notified = 'protected'
        end

        # The branch check may need the repository, so it is left to the worker.
        it { is_expected.to be(true) }
      end
    end

    context 'with a successful pipeline' do
      before do
        data[:object_attributes][:status] = 'success'
      end

      it { is_expected.to be(true) }

      context 'when only broken pipelines are notified' do
        let(:notify_only_broken_pipelines) { true }

        it { is_expected.to be(false) }
      end
    end

    %w[running pending created canceled skipped].each do |status|
      context "with a #{status} pipeline" do
        before do
          data[:object_attributes][:status] = status
        end

        it { is_expected.to be(false) }
      end
    end

    context 'with an event other than pipeline' do
      before do
        data[:object_kind] = 'push'
      end

      it { is_expected.to be(true) }
    end

    it 'does not check the branch or pipeline source' do
      expect(integration).not_to receive(:notify_for_branch?)
      expect(integration).not_to receive(:notify_for_pipeline_source?)

      should_enqueue
    end
  end

  describe '#test' do
    def run
      subject.test(data)
    end

    context 'when pipeline is failed and on default branch' do
      it_behaves_like 'sending email'
    end

    context 'when pipeline is succeeded' do
      before do
        data[:object_attributes][:status] = 'success'
        pipeline.update!(status: 'success')
      end

      it_behaves_like 'sending email'
    end

    context 'when the pipeline failed' do
      context 'on default branch' do
        before do
          data[:object_attributes][:ref] = project.default_branch
          pipeline.update!(ref: project.default_branch)
        end

        context 'when notifications are enabled only for default branch' do
          it_behaves_like 'sending email', branches_to_be_notified: "default"
        end

        context 'when notifications are enabled only for protected branch' do
          it_behaves_like 'sending email', branches_to_be_notified: "protected"
        end

        context 'when notifications are enabled only for default and protected branches' do
          it_behaves_like 'sending email', branches_to_be_notified: "default_and_protected"
        end

        context 'when notifications are enabled only for all branches' do
          it_behaves_like 'sending email', branches_to_be_notified: "all"
        end
      end

      context 'on a protected branch' do
        before do
          create(:protected_branch, project: project, name: 'a-protected-branch')
          data[:object_attributes][:ref] = 'a-protected-branch'
          pipeline.update!(ref: 'a-protected-branch')
        end

        context 'when notifications are enabled only for default branch' do
          it_behaves_like 'sending email', branches_to_be_notified: "default"
        end

        context 'when notifications are enabled only for protected branch' do
          it_behaves_like 'sending email', branches_to_be_notified: "protected"
        end

        context 'when notifications are enabled only for default and protected branches' do
          it_behaves_like 'sending email', branches_to_be_notified: "default_and_protected"
        end

        context 'when notifications are enabled only for all branches' do
          it_behaves_like 'sending email', branches_to_be_notified: "all"
        end
      end

      context 'on a neither protected nor default branch' do
        before do
          data[:object_attributes][:ref] = 'a-random-branch'
          pipeline.update!(ref: 'a-random-branch')
        end

        context 'when notifications are enabled only for default branch' do
          it_behaves_like 'sending email', branches_to_be_notified: "default"
        end

        context 'when notifications are enabled only for protected branch' do
          it_behaves_like 'sending email', branches_to_be_notified: "protected"
        end

        context 'when notifications are enabled only for default and protected branches' do
          it_behaves_like 'sending email', branches_to_be_notified: "default_and_protected"
        end

        context 'when notifications are enabled only for all branches' do
          it_behaves_like 'sending email', branches_to_be_notified: "all"
        end
      end
    end
  end

  describe '#execute' do
    before do
      subject.project = project
    end

    def run
      subject.execute(data)
    end

    context 'with recipients' do
      context 'with succeeded pipeline' do
        before do
          data[:object_attributes][:status] = 'success'
          pipeline.update!(status: 'success')
        end

        it_behaves_like 'not sending email'
      end

      context 'with notify_only_broken_pipelines on' do
        before do
          subject.notify_only_broken_pipelines = true
        end

        context 'with failed pipeline' do
          it_behaves_like 'sending email'
        end

        context 'with succeeded pipeline' do
          before do
            data[:object_attributes][:status] = 'success'
            pipeline.update!(status: 'success')
          end

          it_behaves_like 'not sending email'
        end
      end

      context 'with pipeline and ref status' do
        it_behaves_like 'pipeline notification integration', 'PipelinesEmail'
      end

      context 'when the pipeline failed' do
        context 'on default branch' do
          it_behaves_like 'sending email'

          context 'when notifications are enabled only for default branch' do
            it_behaves_like 'sending email', branches_to_be_notified: "default"
          end

          context 'when notifications are enabled only for protected branch' do
            it_behaves_like 'not sending email', branches_to_be_notified: "protected"
          end

          context 'when notifications are enabled only for default and protected branches' do
            it_behaves_like 'sending email', branches_to_be_notified: "default_and_protected"
          end

          context 'when notifications are enabled only for all branches' do
            it_behaves_like 'sending email', branches_to_be_notified: "all"
          end
        end

        context 'on a protected branch' do
          before do
            create(:protected_branch, project: project, name: 'a-protected-branch')
            data[:object_attributes][:ref] = 'a-protected-branch'
            pipeline.update!(ref: 'a-protected-branch')
          end

          context 'when notifications are enabled only for default branch' do
            it_behaves_like 'not sending email', branches_to_be_notified: "default"
          end

          context 'when notifications are enabled only for protected branch' do
            it_behaves_like 'sending email', branches_to_be_notified: "protected"
          end

          context 'when notifications are enabled only for default and protected branches' do
            it_behaves_like 'sending email', branches_to_be_notified: "default_and_protected"
          end

          context 'when notifications are enabled only for all branches' do
            it_behaves_like 'sending email', branches_to_be_notified: "all"
          end
        end

        context 'on a neither protected nor default branch' do
          before do
            data[:object_attributes][:ref] = 'a-random-branch'
            pipeline.update!(ref: 'a-random-branch')
          end

          context 'when notifications are enabled only for default branch' do
            it_behaves_like 'not sending email', branches_to_be_notified: "default"
          end

          context 'when notifications are enabled only for protected branch' do
            it_behaves_like 'not sending email', branches_to_be_notified: "protected"
          end

          context 'when notifications are enabled only for default and protected branches' do
            it_behaves_like 'not sending email', branches_to_be_notified: "default_and_protected"
          end

          context 'when notifications are enabled only for all branches' do
            it_behaves_like 'sending email', branches_to_be_notified: "all"
          end
        end

        context 'on a tag whose commit is on the default branch' do
          before do
            pipeline.update!(tag: true, ref: 'v1.0.0')
          end

          it_behaves_like 'sending email', branches_to_be_notified: 'default'
          it_behaves_like 'sending email', branches_to_be_notified: 'default_and_protected'
          it_behaves_like 'sending email', branches_to_be_notified: 'all'
          it_behaves_like 'not sending email', branches_to_be_notified: 'protected'
        end
      end
    end

    context 'with empty recipients list' do
      let(:recipients) { ' ,, ' }

      context 'with failed pipeline' do
        before do
          data[:object_attributes][:status] = 'failed'
          pipeline.update!(status: 'failed')
        end

        it_behaves_like 'not sending email'
      end
    end

    context 'with recipients list separating with newlines' do
      let(:recipients) { "\ntest@gitlab.com,  \r\nexample@gitlab.com\rother@gitlab.com" }
      let(:receivers) { %w[test@gitlab.com example@gitlab.com other@gitlab.com] }

      context 'with failed pipeline' do
        before do
          data[:object_attributes][:status] = 'failed'
          pipeline.update!(status: 'failed')
        end

        it_behaves_like 'sending email'
      end
    end

    context 'with invalid recipients' do
      it 'skips the invalid email' do
        subject.recipients = "test@gitlab.com, invalid-email, , another-invalid valid@gitlab.com"

        expect_next_instance_of(PipelineNotificationWorker) do |worker|
          expect(worker).to receive(:perform).with(pipeline.id, "recipients" => ['test@gitlab.com', 'valid@gitlab.com'])
        end

        subject.execute(data)
      end
    end

    context 'when recipient contains angle brackets' do
      it 'removes the angle brackets' do
        subject.recipients = 'Name <valid@recipient.com>, Name 2 valid2@recipient.com'

        expect_next_instance_of(PipelineNotificationWorker) do |worker|
          expect(worker).to receive(:perform).with(pipeline.id,
            "recipients" => ['valid@recipient.com', 'valid2@recipient.com'])
        end

        subject.execute(data)
      end
    end

    context 'with child pipeline notifications' do
      before do
        stub_feature_flags(pipelines_email_notify_child_pipelines: true)
      end

      let(:child_pipeline) do
        create(:ci_pipeline, :failed,
          project: project,
          sha: project.commit('master').sha,
          ref: project.default_branch,
          source: :parent_pipeline
        )
      end

      let(:child_data) do
        Gitlab::DataBuilder::Pipeline.build(child_pipeline)
      end

      def run
        subject.execute(child_data)
      end

      context 'when notify_child_pipelines is enabled' do
        before do
          subject.notify_child_pipelines = true
        end

        it_behaves_like 'sending email'
      end

      context 'when notify_child_pipelines is disabled' do
        before do
          subject.notify_child_pipelines = false
        end

        it_behaves_like 'not sending email'
      end

      context 'when notify_child_pipelines is enabled for parent pipelines' do
        def run
          subject.execute(data) # regular pipeline data
        end

        before do
          subject.notify_child_pipelines = true
        end

        it_behaves_like 'sending email'
      end
    end

    context 'when feature flag is disabled' do
      before do
        stub_feature_flags(pipelines_email_notify_child_pipelines: false)
      end

      context 'with child pipeline' do
        let(:child_pipeline) do
          create(:ci_pipeline, :failed,
            project: project,
            sha: project.commit('master').sha,
            ref: project.default_branch,
            source: :parent_pipeline
          )
        end

        let(:child_data) do
          Gitlab::DataBuilder::Pipeline.build(child_pipeline)
        end

        def run
          subject.execute(child_data)
        end

        before do
          subject.notify_child_pipelines = false
          subject.recipients = recipients
        end

        it_behaves_like 'sending email'
      end
    end

    context 'with rate limiting' do
      let(:recipients) { 'a@gitlab.com,b@gitlab.com,c@gitlab.com' }

      before do
        subject.recipients = recipients
      end

      context 'when over the limit' do
        before do
          allow_next_instance_of(::Gitlab::Email::NamespaceRateLimiter) do |limiter|
            allow(limiter).to receive(:rate_limit_batch!).and_return(true)
          end
        end

        it 'suppresses the whole batch and does not enqueue', :aggregate_failures do
          expect(PipelineNotificationWorker).not_to receive(:new)

          subject.execute(data)
        end

        it 'charges the limiter with the full recipient count' do
          expect_next_instance_of(::Gitlab::Email::NamespaceRateLimiter) do |limiter|
            expect(limiter).to receive(:rate_limit_batch!).with(3).and_return(true)
          end

          subject.execute(data)
        end

        it 'builds the limiter scoped to the root namespace with the Pipelines Email buckets' do
          expect(::Gitlab::Email::NamespaceRateLimiter).to receive(:new).with(
            a_hash_including(
              root_namespace: project.root_namespace,
              hourly_bucket: :pipelines_email_outbound_emails_per_hour,
              daily_bucket: :pipelines_email_outbound_emails_per_day
            )
          ).and_call_original

          subject.execute(data)
        end

        it 'skips the limiter on the forced test path and still enqueues', :aggregate_failures do
          expect(::Gitlab::Email::NamespaceRateLimiter).not_to receive(:new)

          expect_next_instance_of(PipelineNotificationWorker) do |worker|
            expect(worker).to receive(:perform).with(
              pipeline.id, 'recipients' => %w[a@gitlab.com b@gitlab.com c@gitlab.com]
            )
          end

          subject.execute(data, force: true)
        end
      end

      context 'when under the limit' do
        before do
          allow_next_instance_of(::Gitlab::Email::NamespaceRateLimiter) do |limiter|
            allow(limiter).to receive(:rate_limit_batch!).and_return(false)
          end
        end

        it 'enqueues normally' do
          expect_next_instance_of(PipelineNotificationWorker) do |worker|
            expect(worker).to receive(:perform).with(
              pipeline.id, 'recipients' => %w[a@gitlab.com b@gitlab.com c@gitlab.com]
            )
          end

          subject.execute(data)
        end
      end

      context 'when emails are disabled for the project' do
        before do
          allow(project).to receive(:emails_disabled?).and_return(true)
        end

        it 'does not charge the limiter and does not enqueue', :aggregate_failures do
          expect(::Gitlab::Email::NamespaceRateLimiter).not_to receive(:new)
          expect(PipelineNotificationWorker).not_to receive(:new)

          subject.execute(data)
        end
      end
    end
  end

  describe '#should_pipeline_be_notified?', :aggregate_failures do
    subject(:integration) { described_class.new(project: project) }

    before do
      data[:object_attributes][:tag] = true
      data[:object_attributes][:ref] = 'v1.0.0'
    end

    context 'with a non-final pipeline status' do
      using RSpec::Parameterized::TableSyntax

      where(:status) { %w[created pending running canceled skipped] }

      with_them do
        it 'does not look up branches or commit ancestry' do
          data[:object_attributes][:status] = status

          expect(project.repository).not_to receive(:branch_names_contains)
          expect(project.repository).not_to receive(:ancestor?)

          expect(integration.should_pipeline_be_notified?(data)).to be(false)
        end
      end
    end

    it 'does not look up branches when the pipeline source is excluded' do
      allow(integration).to receive(:notify_for_pipeline_source?).with(data).and_return(false)

      expect(project.repository).not_to receive(:branch_names_contains)
      expect(project.repository).not_to receive(:ancestor?)

      expect(integration.should_pipeline_be_notified?(data)).to be(false)
    end
  end

  describe '#notify_for_branch?', :aggregate_failures do
    subject(:integration) { described_class.new(project: project, branches_to_be_notified: selection) }

    let(:selection) { 'default' }

    before do
      data[:object_attributes][:tag] = true
      data[:object_attributes][:ref] = 'v1.0.0'
    end

    context 'with the default branch selected' do
      it 'matches the tag commit without enumerating containing branches' do
        expect(project.repository).not_to receive(:branch_names_contains)

        expect(integration.notify_for_branch?(data)).to be(true)
      end

      it 'rejects a tag commit outside the default branch' do
        data[:object_attributes][:sha] = project.commit('feature').sha

        expect(integration.notify_for_branch?(data)).to be(false)
      end

      it 'rejects a missing commit SHA without a repository lookup' do
        data[:object_attributes][:sha] = nil

        expect(project.repository).not_to receive(:commit)
        expect(integration.notify_for_branch?(data)).to be(false)
      end

      it 'rejects a tag when the default branch commit no longer exists' do
        data
        allow(project.repository).to receive(:commit).with(project.default_branch).and_return(nil)

        expect(integration.notify_for_branch?(data)).to be(false)
      end
    end

    context 'with an unsupported legacy selection' do
      let(:selection) { 'legacy' }

      it 'does not match or look up repository branches' do
        expect(project.repository).not_to receive(:branch_names_contains)
        expect(project.repository).not_to receive(:ancestor?)

        expect(integration.notify_for_branch?(data)).to be(false)
      end
    end

    context 'with all branches selected' do
      let(:selection) { 'all' }

      it 'does not look up branches or commit ancestry' do
        expect(project.repository).not_to receive(:branch_names_contains)
        expect(project.repository).not_to receive(:ancestor?)

        expect(integration.notify_for_branch?(data)).to be(true)
      end
    end

    context 'with protected branches selected' do
      let(:selection) { 'protected' }

      it 'does not check protection when no branch contains the tag commit' do
        allow(project.repository).to receive(:branch_names_contains).with(pipeline.sha).and_return([])
        expect(ProtectedBranch).not_to receive(:any_protected?)

        expect(integration.notify_for_branch?(data)).to be(false)
      end

      it 'rejects a missing commit SHA without a repository lookup' do
        data[:object_attributes][:sha] = nil
        expect(project.repository).not_to receive(:branch_names_contains)

        expect(integration.notify_for_branch?(data)).to be(false)
      end

      it 'does not match when there are no protected branches' do
        expect(integration.notify_for_branch?(data)).to be(false)
      end

      it 'matches wildcard protection rules without per-branch cache lookups' do
        create(:protected_branch, project: project, name: 'release-*')
        branch_names = Array.new(1500) { |index| "feature-#{index}" } << 'release-1'
        expect(project.repository).to receive(:branch_names_contains).with(pipeline.sha).once.and_return(branch_names)
        expect(ProtectedBranch).to receive(:protected_refs).with(project).once.and_call_original
        expect(ProtectedBranch).not_to receive(:protected?)

        expect(integration.notify_for_branch?(data)).to be(true)
      end

      it 'does not match an unprotected containing branch' do
        create(:protected_branch, project: project, name: 'release-*')
        allow(project.repository).to receive(:branch_names_contains).with(pipeline.sha).and_return(['feature-1'])

        expect(integration.notify_for_branch?(data)).to be(false)
      end
    end

    context 'with default and protected branches selected' do
      let(:selection) { 'default_and_protected' }

      it 'stops after matching the default branch' do
        expect(project.repository).not_to receive(:branch_names_contains)
        expect(ProtectedBranch).not_to receive(:protected_refs)

        expect(integration.notify_for_branch?(data)).to be(true)
      end

      it 'matches a protected containing branch outside the default branch' do
        data[:object_attributes][:sha] = project.commit('feature').sha
        create(:protected_branch, project: project, name: 'feature')

        expect(integration.notify_for_branch?(data)).to be(true)
      end
    end
  end
end
