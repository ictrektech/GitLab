# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkItems::AgentPlan, feature_category: :team_planning do
  let_it_be(:project) { create(:project) }

  describe 'associations' do
    it { is_expected.to belong_to(:work_item) }
    it { is_expected.to belong_to(:namespace) }
  end

  describe 'validations' do
    let_it_be(:work_item) { create(:work_item, project: project) }

    it { is_expected.to validate_presence_of(:namespace) }
    it { is_expected.to validate_presence_of(:work_item) }

    it 'sets namespace from work_item before validation' do
      agent_plan = described_class.new(work_item: work_item)

      expect(agent_plan).to be_valid
      expect(agent_plan.namespace).to eq(work_item.namespace)
    end

    it 'does not raise when work_item is nil' do
      agent_plan = described_class.new(work_item: nil)
      agent_plan.valid?
      expect(agent_plan.namespace).to be_nil
    end

    it { is_expected.to validate_length_of(:content).is_at_most(described_class::CONTENT_LENGTH_MAX) }

    describe 'readiness_score' do
      using RSpec::Parameterized::TableSyntax

      where(:score, :valid) do
        nil | true
        0   | true
        100 | true
        -1  | false
        101 | false
      end

      with_them do
        it 'validates the score against the allowed range' do
          agent_plan = build(:work_item_agent_plan, work_item: work_item, readiness_score: score)

          expect(agent_plan.valid?).to eq(valid)
          expect(agent_plan.errors[:readiness_score]).to be_present unless valid
        end
      end

      it 'persists and retrieves the score' do
        agent_plan = create(:work_item_agent_plan, work_item: work_item, readiness_score: 75)

        expect(described_class.find(agent_plan.work_item_id).readiness_score).to eq(75)
      end
    end

    describe '#ai_planning_enabled' do
      it 'allows setting ai_planning_enabled to true' do
        agent_plan = build(:work_item_agent_plan, work_item: work_item)
        agent_plan.ai_planning_enabled = true

        expect(agent_plan).to be_valid
      end

      it 'allows keeping ai_planning_enabled as false' do
        agent_plan = build(:work_item_agent_plan, work_item: work_item)

        expect(agent_plan).to be_valid
        expect(agent_plan.ai_planning_enabled).to be false
      end

      # `create` is required here: on an unsaved record, assigning `false` reverts
      # `ai_planning_enabled` to its column default, so the attribute reads as unchanged and
      # the validation never runs.
      it 'prevents setting ai_planning_enabled back to false once true' do
        agent_plan = create(:work_item_agent_plan, work_item: work_item, ai_planning_enabled: true)
        agent_plan.ai_planning_enabled = false

        expect(agent_plan).not_to be_valid
        expect(agent_plan.errors[:base])
          .to include('AI planning cannot be disabled once it has been enabled.')
      end
    end

    describe 'readiness_score_feedback' do
      it 'allows nil' do
        agent_plan = build(:work_item_agent_plan, work_item: work_item, readiness_score_feedback: nil)

        expect(agent_plan).to be_valid
      end

      it 'allows feedback within the length limit' do
        agent_plan = build(
          :work_item_agent_plan,
          work_item: work_item,
          readiness_score_feedback: 'x' * described_class::CONTENT_LENGTH_MAX
        )

        expect(agent_plan).to be_valid
      end

      it 'rejects feedback exceeding the length limit' do
        agent_plan = build(
          :work_item_agent_plan,
          work_item: work_item,
          readiness_score_feedback: 'x' * (described_class::CONTENT_LENGTH_MAX + 1)
        )

        expect(agent_plan).not_to be_valid
        expect(agent_plan.errors[:readiness_score_feedback]).to be_present
      end
    end
  end

  describe 'external markdown storage' do
    let(:work_item) { create(:work_item, project: project) }

    it 'persists content to object storage and reads it back' do
      agent_plan = create(:work_item_agent_plan, work_item: work_item, content: '**bold text**')

      reloaded = described_class.find(agent_plan.work_item_id)
      expect(reloaded.content).to eq('**bold text**')
    end

    it 'caches rendered content_html in object storage' do
      agent_plan = create(:work_item_agent_plan, work_item: work_item, content: '**bold**')

      reloaded = described_class.find(agent_plan.work_item_id)
      expect(reloaded.content_html).to include('<strong')
      expect(reloaded.content_html).to include('bold</strong>')
    end

    it 'does not load content from storage until accessed' do
      agent_plan = create(:work_item_agent_plan, work_item: work_item, content: 'lazy test')
      reloaded = described_class.find(agent_plan.work_item_id)

      expect(reloaded).to receive(:read_external_payload).with(:content).once.and_call_original

      expect(reloaded.cached_markdown_version).to be_present
      expect(reloaded.content).to eq('lazy test')
    end

    it 'updates content in object storage on save' do
      agent_plan = create(:work_item_agent_plan, work_item: work_item, content: 'original')

      agent_plan.content = 'updated'
      agent_plan.save!

      reloaded = described_class.find(agent_plan.work_item_id)
      expect(reloaded.content).to eq('updated')
      expect(reloaded.content_html).to be_present
    end

    it 'cleans up every payload on destroy' do
      agent_plan = create(
        :work_item_agent_plan, work_item: work_item, content: 'to be deleted', readiness_score_feedback: 'rationale'
      )

      stored_paths = [agent_plan.content_file.path, agent_plan.readiness_score_feedback_file.path]
      expect(stored_paths).to all(satisfy { |path| File.exist?(path) })

      agent_plan.destroy!

      expect(stored_paths).to all(satisfy { |path| !File.exist?(path) })
    end

    describe 'readiness_score_feedback' do
      it 'persists feedback to object storage and reads it back' do
        agent_plan = create(
          :work_item_agent_plan,
          work_item: work_item,
          readiness_score_feedback: '**needs more detail**'
        )

        reloaded = described_class.find(agent_plan.work_item_id)
        expect(reloaded.readiness_score_feedback).to eq('**needs more detail**')
      end

      it 'returns nil when feedback was never set' do
        agent_plan = create(:work_item_agent_plan, work_item: work_item, content: 'plan only')

        reloaded = described_class.find(agent_plan.work_item_id)
        expect(reloaded.readiness_score_feedback).to be_nil
      end

      it 'stores feedback in its own document, separate from content' do
        agent_plan = create(
          :work_item_agent_plan,
          work_item: work_item,
          content: 'plan body',
          readiness_score_feedback: 'score rationale'
        )

        content_blob = Gitlab::Json::SafeParser.parse(File.read(agent_plan.content_file.path))
        feedback_blob = Gitlab::Json::SafeParser.parse(File.read(agent_plan.readiness_score_feedback_file.path))

        expect(content_blob).to include('content' => 'plan body')
        expect(content_blob).not_to have_key('readiness_score_feedback')
        expect(feedback_blob).to include('readiness_score_feedback' => 'score rationale')
      end

      it 'is dropped for a row whose feedback only exists in a pre-split combined payload' do
        agent_plan = create(:work_item_agent_plan, work_item: work_item, content: 'old plan')
        agent_plan.content_file.store!(
          CarrierWave::SanitizedFile.new(
            tempfile: StringIO.new(
              Gitlab::Json.dump({ 'content' => 'old plan', 'readiness_score_feedback' => 'old rationale' })
            ),
            filename: agent_plan[:content_file],
            content_type: 'application/json'
          )
        )

        reloaded = described_class.find(agent_plan.work_item_id)

        expect(reloaded.content).to eq('old plan')
        expect(reloaded.readiness_score_feedback).to be_nil
      end
    end

    context 'when the cached Markdown version is outdated' do
      let(:agent_plan) { create(:work_item_agent_plan, work_item: work_item, content: '**bold**') }
      let(:current_version) { Gitlab::MarkdownCache.cached_markdown_version_for_write(local_version: nil) }
      let(:old_html) { '<p><b>bold</b></p>' }

      before do
        allow(Gitlab::MarkdownCache).to receive(:latest_cached_markdown_version).and_return(current_version)

        agent_plan.content_file.store!(
          CarrierWave::SanitizedFile.new(
            tempfile: StringIO.new(Gitlab::Json.dump('content' => '**bold**', 'content_html' => old_html)),
            filename: agent_plan[:content_file],
            content_type: 'application/json'
          )
        )
        agent_plan.update_column(:cached_markdown_version, current_version - 1)
      end

      it 'reports the cached HTML as stale', :aggregate_failures do
        reloaded = described_class.find(agent_plan.work_item_id)

        expect(reloaded.content_html).to eq(old_html)
        expect(reloaded.cached_markdown_version).to eq(current_version - 1)
        expect(reloaded.cached_html_up_to_date?(:content)).to be false
      end

      it 'regenerates and persists the HTML on refresh', :aggregate_failures do
        reloaded = described_class.find(agent_plan.work_item_id)
        reloaded.refresh_markdown_cache!

        refreshed = described_class.find(agent_plan.work_item_id)
        expect(refreshed.content).to eq('**bold**')
        expect(refreshed.content_html).to include('bold</strong>')
        expect(refreshed.cached_markdown_version).to eq(current_version)
      end
    end
  end

  describe '#has_content?' do
    let(:work_item) { create(:work_item, project: project) }

    it 'is true when created with content' do
      agent_plan = create(:work_item_agent_plan, work_item: work_item, content: 'a plan')

      expect(described_class.find(agent_plan.work_item_id)).to have_content
    end

    it 'is false when the row exists only because AI planning was enabled' do
      agent_plan = described_class.create!(work_item: work_item, ai_planning_enabled: true)

      expect(described_class.find(agent_plan.work_item_id)).not_to have_content
    end

    it 'flips to false when content is cleared on an existing row' do
      agent_plan = create(:work_item_agent_plan, work_item: work_item, content: 'a plan')

      agent_plan.content = nil
      agent_plan.save!

      expect(described_class.find(agent_plan.work_item_id)).not_to have_content
    end

    it 'flips to true when content is added to a content-less row' do
      agent_plan = described_class.create!(work_item: work_item, ai_planning_enabled: true)

      agent_plan.content = 'a plan'
      agent_plan.save!

      expect(described_class.find(agent_plan.work_item_id)).to have_content
    end

    it 'treats blank content as no content' do
      agent_plan = described_class.create!(work_item: work_item, content: '')

      expect(described_class.find(agent_plan.work_item_id)).not_to have_content
    end

    it 'does not read object storage' do
      agent_plan = create(:work_item_agent_plan, work_item: work_item, content: 'a plan')

      reloaded = described_class.find(agent_plan.work_item_id)
      expect(reloaded).not_to receive(:read_external_payload)

      expect(reloaded).to have_content
    end

    it 'is false for a plan that has only readiness score feedback' do
      agent_plan = described_class.create!(work_item: work_item, readiness_score_feedback: 'rationale')

      reloaded = described_class.find(agent_plan.work_item_id)

      expect(reloaded.readiness_score_feedback).to eq('rationale')
      expect(reloaded).not_to have_content
    end
  end

  describe 'stored payloads' do
    let(:work_item) { create(:work_item, project: project) }

    it 'stores nothing for a row created without content' do
      agent_plan = described_class.create!(work_item: work_item, ai_planning_enabled: true)

      expect(agent_plan[:content_file]).to be_nil
      expect(agent_plan[:readiness_score_feedback_file]).to be_nil
    end

    it 'names each payload after itself, under the record\'s hashed directory' do
      agent_plan = create(
        :work_item_agent_plan, work_item: work_item, content: 'a plan', readiness_score_feedback: 'rationale'
      )

      expect(agent_plan[:content_file]).to eq('content.json')
      expect(agent_plan[:readiness_score_feedback_file]).to eq('readiness_score_feedback.json')
      expect(agent_plan.content_file.path)
        .to end_with("work_item_agent_plans/#{work_item.id}/content.json")
    end

    it 'keeps writing to a payload that predates the split, rather than moving it' do
      agent_plan = create(:work_item_agent_plan, work_item: work_item, content: 'a plan')
      legacy_name = "#{work_item.id}.json"
      stored_dir = File.dirname(agent_plan.content_file.path)
      FileUtils.mv(agent_plan.content_file.path, File.join(stored_dir, legacy_name))
      agent_plan.update_column(:content_file, legacy_name)

      reloaded = described_class.find(agent_plan.work_item_id)
      expect(reloaded.content).to eq('a plan')

      reloaded.content = 'an edited plan'
      reloaded.save!

      expect(reloaded.reload[:content_file]).to eq(legacy_name)
      expect(File.exist?(File.join(stored_dir, 'content.json'))).to be false
      expect(described_class.find(agent_plan.work_item_id).content).to eq('an edited plan')
    end

    it 'removes only the cleared payload' do
      agent_plan = create(
        :work_item_agent_plan, work_item: work_item, content: 'a plan', readiness_score_feedback: 'rationale'
      )
      content_path = agent_plan.content_file.path
      feedback_path = agent_plan.readiness_score_feedback_file.path

      agent_plan.content = nil
      agent_plan.save!

      expect(File.exist?(content_path)).to be false
      expect(File.exist?(feedback_path)).to be true
      expect(agent_plan.reload[:content_file]).to be_nil
      expect(agent_plan[:readiness_score_feedback_file]).to eq('readiness_score_feedback.json')
    end
  end
end
