# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Integrations::SlackInteractions::DuoToolRequestModal, feature_category: :duo_agent_platform do
  let(:issue_entry) do
    {
      'message_type' => 'request',
      'message_id' => 'toolu_01issue',
      'content' => 'Creating the bug report <you> asked for',
      'tool_info' => { 'name' => 'create_issue', 'args' => { 'title' => 'Bug report', 'force' => true } }
    }
  end

  let(:entries) { [issue_entry] }
  let(:pending) { Ai::DuoWorkflows::PendingToolApproval.new(entries) }
  let(:session_url) { 'https://gitlab.example.com/duo/sessions/42' }

  def preformatted_text(block)
    block.dig(:elements, 0, :elements, 0, :text)
  end

  describe '#build' do
    subject(:view) { described_class.new(pending, session_url: session_url).build }

    it 'is a read-only modal titled like the card, with no submit button', :aggregate_failures do
      expect(view).to include(type: 'modal', title: { type: 'plain_text', text: 'Run Create issue' })
      expect(view).to have_key(:close)
      expect(view).not_to have_key(:submit)
      expect(view).not_to have_key(:callback_id)
    end

    context 'when the card title is longer than a modal title allows' do
      let(:entries) do
        [issue_entry,
          issue_entry.merge('message_id' => 'toolu_02',
            'tool_info' => { 'name' => 'create_merge_request', 'args' => {} })]
      end

      it 'truncates it to 24 characters' do
        expect(view[:title][:text].length).to be <= 24
        expect(view[:title][:text]).to start_with('Run Create issue, ')
      end
    end

    it 'shows the tool with its escaped summary, then the complete arguments in one code block', :aggregate_failures do
      summary, args = view[:blocks]

      expect(summary[:text][:text]).to eq("*Create issue*\nCreating the bug report &lt;you&gt; asked for")
      expect(args).to eq(
        type: 'rich_text',
        elements: [{
          type: 'rich_text_preformatted',
          elements: [{ type: 'text', text: Gitlab::Json.pretty_generate('title' => 'Bug report', 'force' => true) }]
        }]
      )
    end

    context 'when the arguments contain Slack control sequences' do
      let(:issue_entry) do
        super().merge('tool_info' => { 'name' => 'notify', 'args' => { 'description' => '<!channel> & <@U999>' } })
      end

      it 'keeps them verbatim in the preformatted block, where Slack does not parse mrkdwn' do
        expect(preformatted_text(view[:blocks].last)).to include('"<!channel> & <@U999>"')
      end
    end

    context 'when the arguments are far larger than a section allows' do
      let(:issue_entry) do
        super().merge('tool_info' => { 'name' => 'create_file', 'args' => { 'content' => 'x' * 50_000 } })
      end

      it 'renders them as a single uncut code block' do
        code_blocks = view[:blocks].select { |b| b[:type] == 'rich_text' }

        expect(code_blocks.size).to eq(1)
        expect(preformatted_text(code_blocks.sole)).to eq(Gitlab::Json.pretty_generate('content' => 'x' * 50_000))
      end
    end

    context 'when the payload exceeds what a view can hold' do
      let(:issue_entry) do
        super().merge('tool_info' => { 'name' => 'create_file', 'args' => { 'content' => 'x' * 250_000 } })
      end

      it 'shows the head of the arguments and points to the session in GitLab', :aggregate_failures do
        *head, args, note = view[:blocks]

        expect(head.map { |b| b[:type] }).to eq(%w[section])
        expect(preformatted_text(args).length).to be <= described_class::VIEW_MAX_LENGTH
        expect(preformatted_text(args)).to start_with("{\n  \"content\": \"xxx")
        expect(note[:elements].sole[:text]).to include('too large to show here in full')
      end
    end

    context 'when a later call does not fit in what is left of the view' do
      let(:entries) do
        [
          issue_entry.merge('tool_info' => { 'name' => 'create_file', 'args' => { 'content' => 'x' * 179_500 } }),
          issue_entry.merge('message_id' => 'toolu_02', 'content' => 'y' * 2000,
            'tool_info' => { 'name' => 'create_merge_request', 'args' => {} })
        ]
      end

      it 'keeps the first call whole and replaces the rest with the overflow note', :aggregate_failures do
        *kept, note = view[:blocks]

        expect(kept.map { |b| b[:type] }).to eq(%w[section rich_text divider])
        expect(view.to_json).not_to include('Create merge request')
        expect(note[:elements].sole[:text]).to include('too large to show here in full')
      end
    end

    context 'with several calls' do
      let(:entries) do
        [issue_entry, issue_entry.merge('message_id' => 'toolu_02', 'tool_info' => { 'name' => 'x', 'args' => {} })]
      end

      it 'separates them with dividers and skips empty arguments' do
        expect(view[:blocks].map { |b| b[:type] }).to eq(%w[section rich_text divider section])
      end
    end

    context 'when the payload needs more than 100 blocks' do
      let(:entries) do
        Array.new(40) do |index|
          issue_entry.merge('message_id' => "toolu_#{index}",
            'tool_info' => { 'name' => 'tool', 'args' => { 'i' => index } })
        end
      end

      it 'caps the view and points to the session in GitLab', :aggregate_failures do
        expect(view[:blocks].size).to eq(100)
        expect(view[:blocks].last).to eq(
          type: 'context',
          elements: [{
            type: 'mrkdwn',
            text: "The request is too large to show here in full. <#{session_url}|Open the session in GitLab>."
          }]
        )
      end

      context 'without a session url' do
        let(:session_url) { nil }

        it 'still caps the view' do
          expect(view[:blocks].last[:elements].sole[:text])
            .to eq('The request is too large to show here in full. Open the session in GitLab.')
        end
      end
    end
  end

  describe '.stale_view' do
    it 'tells the viewer the request was already answered' do
      expect(described_class.stale_view[:blocks].sole[:text][:text])
        .to eq('This approval request has already been answered.')
    end
  end
end
