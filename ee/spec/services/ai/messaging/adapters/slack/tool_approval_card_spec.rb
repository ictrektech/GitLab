# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::Adapters::Slack::ToolApprovalCard, feature_category: :duo_agent_platform do
  let(:issue_entry) do
    {
      'message_type' => 'request',
      'message_id' => 'toolu_01issue',
      'content' => 'Creating the bug report you asked for',
      'tool_info' => { 'name' => 'create_issue', 'args' => { 'title' => 'Bug report', 'body' => 'It crashes' } }
    }
  end

  let(:entries) { [issue_entry] }
  let(:pending) { Ai::DuoWorkflows::PendingToolApproval.new(entries) }
  let(:requester_id) { 'U0REQUESTER' }
  let(:value) { "42:#{pending.fingerprint}" }

  subject(:card) { described_class.new(pending, workflow_id: 42, requester_id: requester_id) }

  describe '#blocks' do
    let(:container) { card.blocks.sole }
    let(:children) { container[:child_blocks] }
    let(:actions) { children.last }
    let(:details) { children[-2] }

    it 'renders one wide, expanded, collapsible container keyed by the fingerprint', :aggregate_failures do
      expect(card.blocks.size).to eq(1)
      expect(container).to include(
        type: 'container',
        block_id: "duo_approval_#{pending.fingerprint}",
        width: 'wide',
        is_collapsible: true,
        default_collapsed: false
      )
    end

    it 'puts the tool in the title and the requester in the subtitle', :aggregate_failures do
      expect(container[:title]).to eq(type: 'plain_text', text: 'Run Create issue')
      expect(container[:subtitle]).to eq(type: 'mrkdwn', text: 'Waiting for <@U0REQUESTER>')
    end

    it 'shows the agent summary and the full arguments for the call', :aggregate_failures do
      section, rich_text = children.first(2)

      expect(section[:text][:text]).to eq("*Create issue*\nCreating the bug report you asked for")
      expect(rich_text[:elements].sole[:type]).to eq('rich_text_preformatted')
      expect(rich_text[:elements].sole[:elements].sole[:text])
        .to eq(Gitlab::Json.pretty_generate('title' => 'Bug report', 'body' => 'It crashes'))
    end

    it 'ends with Approve on the outside edge, then Deny, both carrying the workflow id and fingerprint',
      :aggregate_failures do
      expect(actions[:type]).to eq('actions')
      expect(actions[:elements].map { |b| b.values_at(:action_id, :style, :value) }).to eq([
        ['duo_approval_approve', 'primary', value],
        ['duo_approval_deny', 'danger', value]
      ])
    end

    it 'shows the buttons only to the requester' do
      expect(actions[:elements].map { |b| b[:visible_to_user_ids] }).to all(eq(['U0REQUESTER']))
    end

    it 'does not offer the details button when nothing was cut' do
      expect(children.filter_map { |b| b.dig(:accessory, :action_id) }).to be_empty
    end

    context 'when there is no requester' do
      let(:requester_id) { nil }

      it 'falls back to a generic subtitle and public buttons', :aggregate_failures do
        expect(container[:subtitle][:text]).to eq('Waiting for the person who started this session')
        expect(actions[:elements]).to all(exclude(:visible_to_user_ids))
      end
    end

    context 'when the call has no summary or arguments' do
      let(:issue_entry) { super().merge('content' => '', 'tool_info' => { 'name' => 'list_issues', 'args' => {} }) }

      it 'names the tool and skips the arguments block', :aggregate_failures do
        expect(children.first[:text][:text]).to eq("*List issues*\nGitLab Duo wants to run this tool.")
        expect(children.map { |b| b[:type] }).to eq(%w[section actions])
      end
    end

    context 'when the summary contains Slack control sequences' do
      let(:issue_entry) { super().merge('content' => 'Ping <!channel> & <@U999>') }

      it 'escapes them so model output cannot page the channel' do
        expect(children.first[:text][:text]).to eq("*Create issue*\nPing &lt;!channel&gt; &amp; &lt;@U999&gt;")
      end
    end

    context 'when the summary exceeds a Slack section' do
      let(:issue_entry) { super().merge('content' => 'word ' * 1000) }

      it 'truncates it and offers the details button', :aggregate_failures do
        expect(children.first[:text][:text].length).to be <= 1000
        expect(children.first[:text][:text]).to end_with('…')
        expect(details[:accessory][:action_id]).to eq('duo_approval_details')
      end
    end

    describe 'truncating the summary' do
      let(:kept_words) { children.first[:text][:text].split("\n", 2).last.delete_suffix('…').split(' ') }

      context 'when the cap falls inside a word' do
        let(:issue_entry) { super().merge('content' => 'supercalifragilistic ' * 100) }

        it 'cuts at the word boundary before it' do
          expect(kept_words).to all(eq('supercalifragilistic'))
          expect(kept_words.size).to be_between(1, 99)
        end
      end

      context 'when the cap falls inside an escaped character' do
        let(:issue_entry) { super().merge('content' => 'a& ' * 300) }

        it 'keeps every escape sequence whole' do
          expect(kept_words).to all(eq('a&amp;'))
          expect(kept_words.size).to be_between(1, 299)
        end
      end
    end

    context 'when a summary under the cap grows past it once escaped' do
      let(:issue_entry) { super().merge('content' => '<a> & ' * 150) }

      it 'measures the escaped text so the section stays within the cap', :aggregate_failures do
        text = children.first[:text][:text]

        expect(text.length).to be <= 1000
        expect(text).to include('&lt;a&gt; &amp;')
        expect(text).to end_with('…')
        expect(details[:accessory][:action_id]).to eq('duo_approval_details')
      end
    end

    context 'when the arguments exceed the inline budget' do
      let(:issue_entry) do
        super().merge('tool_info' => { 'name' => 'create_file', 'args' => { 'content' => 'x' * 10_000 } })
      end

      it 'shows the head and offers the details button next to a note, right-aligned', :aggregate_failures do
        text = children.second[:elements].sole[:elements].sole[:text]

        expect(text).to start_with(Gitlab::Json.pretty_generate('content' => 'x' * 10_000).first(1200))
        expect(text.length).to be <= 1202
        expect(text).to end_with("\n…")
        expect(details[:text][:text]).to eq('The arguments are cut to fit this message.')
        expect(details[:accessory]).to include(
          type: 'button', action_id: 'duo_approval_details', value: value, visible_to_user_ids: ['U0REQUESTER']
        )
        expect(details[:accessory]).not_to have_key(:style)
        expect(actions[:elements].map { |b| b[:action_id] }).to eq(%w[duo_approval_approve duo_approval_deny])
      end
    end

    context 'when more calls are pending than fit in a container' do
      let(:entries) do
        Array.new(6) do |index|
          issue_entry.merge('message_id' => "toolu_#{index}",
            'tool_info' => { 'name' => "tool_#{index}", 'args' => {} })
        end
      end

      it 'renders the first four, notes the rest and offers the details button', :aggregate_failures do
        expect(children.size).to be <= 10
        expect(children.count { |b| b[:type] == 'section' && !b.key?(:accessory) }).to eq(4)
        expect(details[:text][:text]).to eq('2 more actions are not shown here.')
        expect(details[:accessory][:action_id]).to eq('duo_approval_details')
      end

      it 'lists every pending tool in the title, humanized' do
        expect(container[:title][:text]).to eq('Run Tool 0, Tool 1, Tool 2, Tool 3, Tool 4, Tool 5')
      end

      context 'when exactly one call is hidden' do
        let(:entries) { super().first(5) }

        it 'uses the singular form' do
          expect(details[:text][:text]).to eq('1 more action is not shown here.')
        end
      end
    end

    context 'when the tool names overflow the title' do
      let(:entries) do
        Array.new(12) do |index|
          issue_entry.merge('message_id' => "toolu_#{index}",
            'tool_info' => { 'name' => "a_rather_long_tool_name_#{index}", 'args' => {} })
        end
      end

      it 'truncates at a tool boundary within 150 characters', :aggregate_failures do
        expect(container[:title][:text].length).to be <= 150
        expect(container[:title][:text]).to end_with('...')
      end
    end

    context 'when the request starts a flow' do
      let(:entries) do
        [issue_entry.merge('tool_info' => { 'name' => 'start_flow', 'args' => { 'flow' => flow_args } })]
      end

      let(:flow_args) { { 'name' => 'fix_pipeline', 'merge_request_url' => 'https://example.test/mr/1' } }

      it 'names the flow in the title' do
        expect(container[:title][:text]).to eq('Start the Fix pipeline flow')
      end

      context 'when it is a custom flow' do
        let(:flow_args) { { 'name' => 'catalog_flow', 'ai_catalog_item_consumer_id' => 7 } }

        it 'calls it a custom flow' do
          expect(container[:title][:text]).to eq('Start a custom flow')
        end
      end
    end

    context 'with a decision' do
      let(:container) { card.blocks(decision: :approved, decided_by: 'U0DECIDER').sole }

      it 'keeps the payload, replaces the buttons, marks the subtitle and collapses the card', :aggregate_failures do
        expect(container[:subtitle][:text]).to eq('Approved')
        expect(container[:default_collapsed]).to be(true)
        expect(children.map { |b| b[:type] }).to eq(%w[section rich_text context])
        expect(children.last[:elements].sole[:text])
          .to eq('Approved by <@U0DECIDER>. GitLab Duo is continuing.')
      end

      context 'when denied' do
        let(:container) { card.blocks(decision: :denied, decided_by: 'U0DECIDER').sole }

        it 'names the decider in the denial', :aggregate_failures do
          expect(container[:subtitle][:text]).to eq('Denied')
          expect(children.last[:elements].sole[:text])
            .to eq('Denied by <@U0DECIDER>. GitLab Duo is continuing without running these actions.')
        end
      end

      context 'when denied without a known decider' do
        let(:container) { card.blocks(decision: :denied).sole }

        it 'states the denial only', :aggregate_failures do
          expect(container[:subtitle][:text]).to eq('Denied')
          expect(children.last[:elements].sole[:text])
            .to eq('Denied. GitLab Duo is continuing without running these actions.')
        end
      end
    end
  end

  describe '.flow_request_text' do
    let(:start_flow_entry) do
      {
        'message_type' => 'request',
        'message_id' => 'toolu_01flow',
        'content' => 'Starting a flow',
        'tool_info' => { 'name' => 'start_flow', 'args' => { 'flow' => flow_args } }
      }
    end

    let(:flow_args) { { 'name' => 'developer', 'goal' => 'Add a "Local setup" section to the README' } }
    let(:entries) { [start_flow_entry] }

    subject(:text) { described_class.flow_request_text(pending) }

    it 'names the flow and quotes the goal' do
      expect(text).to eq(
        'GitLab Duo wants to start the Developer flow: "Add a "Local setup" section to the README". ' \
          'Open to approve or deny.'
      )
    end

    context 'when the goal is long' do
      let(:flow_args) { { 'name' => 'developer', 'goal' => "Refactor the  importer\n#{'word ' * 40}" } }

      it 'quotes its first words on one line', :aggregate_failures do
        goal = text[/"(.*)"/, 1]

        expect(goal.length).to be <= described_class::GOAL_PREVIEW_MAX_LENGTH
        expect(goal).to start_with('Refactor the importer word').and end_with('…')
      end
    end

    context 'when the goal contains Slack control sequences' do
      let(:flow_args) { { 'name' => 'developer', 'goal' => 'Ping <!channel> & fix' } }

      it 'escapes them' do
        expect(text).to include('"Ping &lt;!channel&gt; &amp; fix"')
      end
    end

    context 'when the flow has no goal' do
      let(:flow_args) { { 'name' => 'fix_pipeline', 'merge_request_url' => 'https://example.test/mr/1' } }

      it 'names the flow only' do
        expect(text).to eq('GitLab Duo wants to start the Fix pipeline flow. Open to approve or deny.')
      end
    end

    context 'when it is a custom flow' do
      let(:flow_args) { { 'name' => 'catalog_flow', 'ai_catalog_item_consumer_id' => 7, 'goal' => 'Triage' } }

      it 'calls it a custom flow and quotes the goal' do
        expect(text).to eq('GitLab Duo wants to start a custom flow: "Triage". Open to approve or deny.')
      end

      context 'without a goal' do
        let(:flow_args) { { 'name' => 'catalog_flow', 'ai_catalog_item_consumer_id' => 7 } }

        it 'calls it a custom flow' do
          expect(text).to eq('GitLab Duo wants to start a custom flow. Open to approve or deny.')
        end
      end
    end

    context 'when start_flow is one of several pending calls' do
      let(:entries) { [start_flow_entry, issue_entry] }

      it { is_expected.to be_nil }
    end

    context 'when the request is for another tool' do
      let(:entries) { [issue_entry] }

      it { is_expected.to be_nil }
    end

    context 'when the flow name contains Slack control sequences' do
      let(:flow_args) { { 'name' => '<!channel>' } }

      it 'escapes it' do
        expect(text).to include('&lt;!channel&gt;').and exclude('<!channel>')
      end
    end

    context 'when the request carries no flow arguments' do
      let(:start_flow_entry) { super().merge('tool_info' => { 'name' => 'start_flow', 'args' => {} }) }

      it 'falls back to the generic text and title', :aggregate_failures do
        expect(text).to be_nil
        expect(described_class.title(pending)).to eq('Run Start flow')
      end
    end
  end

  describe '.outcome_text' do
    it 'describes both outcomes', :aggregate_failures do
      expect(described_class.outcome_text(:approved)).to eq('Approved. GitLab Duo is continuing.')
      expect(described_class.outcome_text(:denied))
        .to eq('Denied. GitLab Duo is continuing without running these actions.')
    end
  end
end
