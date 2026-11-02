# frozen_string_literal: true

require 'fast_spec_helper'
require 'open3'
require 'rspec-parameterized'
require 'socket'
require 'stringio'
require 'tmpdir'
require 'webmock/rspec'

load File.expand_path('../../scripts/slack', __dir__)

RSpec.describe 'scripts/slack', feature_category: :tooling do
  let(:script) { File.expand_path('../../scripts/slack', __dir__) }
  let(:webhook_url) { 'https://hooks.example.test/webhook' }
  let(:message) { 'job failed' }
  let(:icon_emoji) { 'ci_failing' }
  let(:username) { 'GitLab Bot' }
  let(:output) { StringIO.new }
  let(:post_message_url) { 'https://slack.com/api/chat.postMessage' }
  let(:usage_hint) { 'and set CI_SLACK_BOT_TOKEN (or CI_SLACK_WEBHOOK_URL) environment variable.' }

  def notify(*args, url: webhook_url, token: nil)
    SlackNotifier.new(args, webhook_url: url, bot_token: token, output: output).execute
  end

  def posted_payload(request)
    Gitlab::Json::SafeParser.parse(URI.decode_www_form(request.body).to_h.fetch('payload'))
  end

  def stub_webhook(body: 'ok', status: 200)
    stub_request(:post, webhook_url).to_return(status: status, body: body)
  end

  describe '.target' do
    where(:channel, :expected_target) do
      [
        ['master-broken', '#master-broken'],
        ['g_pipeline-authoring_alerts', '#g_pipeline-authoring_alerts'],
        ['CR6QH3D7C', 'CR6QH3D7C'],
        ['C0123456789', 'C0123456789'],
        ['G0123456789', 'G0123456789'],
        # Too short to be an ID, so it is treated as a name.
        ['CABC', '#CABC'],
        # Starts with neither C nor G.
        ['D0123456789', '#D0123456789'],
        # Lowercase never counts as an ID.
        ['c0123456789', '#c0123456789'],
        ['CR6QH3D7C ', '#CR6QH3D7C '],
        ["CR6QH3D7C\n", "#CR6QH3D7C\n"],
        ['xC0123456789', '#xC0123456789'],
        ["name\nC0123456789", "#name\nC0123456789"],
        # Eight characters is one short of an ID; nine is enough.
        ['C1234567', '#C1234567'],
        ['C12345678', 'C12345678'],
        ['Cabcdefgh', '#Cabcdefgh']
      ]
    end

    with_them do
      it 'returns the channel to post to' do
        expect(SlackNotifier.target(channel)).to eq(expected_target)
      end
    end
  end

  describe '#execute' do
    it 'posts the message, username, and icon to the webhook', :aggregate_failures do
      stub_webhook

      expect(notify('master-broken', message, icon_emoji, username)).to eq(0)

      expect(WebMock).to have_requested(:post, webhook_url).with { |request|
        posted_payload(request) == {
          'channel' => '#master-broken',
          'username' => username,
          'text' => message,
          'icon_emoji' => ":#{icon_emoji}:"
        }
      }
    end

    it 'posts a channel ID without a # prefix' do
      stub_webhook

      notify('CR6QH3D7C', message, icon_emoji, username)

      expect(WebMock).to have_requested(:post, webhook_url).with { |request|
        posted_payload(request)['channel'] == 'CR6QH3D7C'
      }
    end

    it 'keeps quotes, backslashes, and newlines in the message intact' do
      stub_webhook
      text = %(say "hi" \\ to <https://example.test|the job>\nsecond line)

      notify('master-broken', text, icon_emoji, username)

      expect(WebMock).to have_requested(:post, webhook_url).with { |request|
        posted_payload(request)['text'] == text
      }
    end

    it 'prints the response body' do
      stub_webhook(body: 'ok')

      notify('master-broken', message, icon_emoji, username)

      expect(output.string).to eq('ok')
    end

    it 'prints the error body and returns zero when Slack rejects the post', :aggregate_failures do
      stub_webhook(status: 404, body: 'channel_not_found')

      expect(notify('master-broken', message, icon_emoji, username)).to eq(0)
      expect(output.string).to eq('channel_not_found')
    end

    it 'raises when the webhook cannot be reached' do
      stub_request(:post, webhook_url).to_raise(SocketError)

      expect { notify('master-broken', message, icon_emoji, username) }.to raise_error(SocketError)
    end

    context 'when an argument is missing' do
      where(:args) do
        [
          [[]],
          [['master-broken']],
          [['master-broken', 'job failed']],
          [['master-broken', 'job failed', 'ci_failing']],
          [['', 'job failed', 'ci_failing', 'GitLab Bot']],
          [['master-broken', '', 'ci_failing', 'GitLab Bot']],
          [['master-broken', 'job failed', '', 'GitLab Bot']],
          [['master-broken', 'job failed', 'ci_failing', '']]
        ]
      end

      with_them do
        it 'does not post, prints the usage, and returns zero', :aggregate_failures do
          expect(notify(*args)).to eq(0)

          expect(WebMock).not_to have_requested(:post, webhook_url)
          expect(output.string).to include('Missing argument(s)', usage_hint)
        end
      end
    end

    context 'when neither CI_SLACK_BOT_TOKEN nor CI_SLACK_WEBHOOK_URL is set' do
      where(:url, :token) { [[nil, nil], ['', ''], [nil, '']] }

      with_them do
        it 'does not post, prints the usage, and returns zero', :aggregate_failures do
          expect(notify('CR6QH3D7C', message, icon_emoji, username, url: url, token: token)).to eq(0)

          expect(WebMock).not_to have_requested(:post, webhook_url)
          expect(WebMock).not_to have_requested(:post, post_message_url)
          expect(output.string).to include('Missing argument(s)', usage_hint)
        end
      end
    end

    context 'with a bot token' do
      let(:bot_token) { 'xoxb-fake-token-for-spec' }
      let(:slack_ok) { '{"ok":true,"channel":"C0123456789","ts":"1792669910.000100"}' }

      def stub_post_message(body: slack_ok, status: 200)
        stub_request(:post, post_message_url).to_return(status: status, body: body)
      end

      def posted_fields(request)
        URI.decode_www_form(request.body).to_h
      end

      it 'posts the fields to chat.postMessage with the token in an Authorization header', :aggregate_failures do
        stub_post_message

        expect(notify('master-broken', message, icon_emoji, username, token: bot_token, url: nil)).to eq(0)

        expect(WebMock).to have_requested(:post, post_message_url)
          .with(headers: { 'Authorization' => "Bearer #{bot_token}" }) { |request|
            posted_fields(request) == {
              'channel' => '#master-broken',
              'username' => username,
              'text' => message,
              'icon_emoji' => ":#{icon_emoji}:"
            }
          }
      end

      it 'posts a channel ID without a # prefix' do
        stub_post_message

        notify('CR6QH3D7C', message, icon_emoji, username, token: bot_token)

        expect(WebMock).to have_requested(:post, post_message_url).with { |request|
          posted_fields(request)['channel'] == 'CR6QH3D7C'
        }
      end

      it 'keeps quotes, ampersands, and shell syntax in the message intact' do
        stub_post_message
        text = %(he said "hi" & left; $(x) `y`\nsecond line)

        notify('master-broken', text, icon_emoji, username, token: bot_token)

        expect(WebMock).to have_requested(:post, post_message_url).with { |request|
          posted_fields(request)['text'] == text
        }
      end

      it 'prefers the token over the webhook and posts once', :aggregate_failures do
        stub_post_message
        stub_webhook

        notify('master-broken', message, icon_emoji, username, token: bot_token)

        expect(WebMock).to have_requested(:post, post_message_url).once
        expect(WebMock).not_to have_requested(:post, webhook_url)
      end

      it 'falls back to the webhook when the token is empty', :aggregate_failures do
        stub_webhook

        notify('master-broken', message, icon_emoji, username, token: '')

        expect(WebMock).to have_requested(:post, webhook_url).once
        expect(WebMock).not_to have_requested(:post, post_message_url)
      end

      it 'prints nothing when Slack accepts the post' do
        stub_post_message

        notify('master-broken', message, icon_emoji, username, token: bot_token)

        expect(output.string).to be_empty
      end

      where(:body) do
        [
          ['{"ok":false,"error":"channel_not_found"}'],
          ['<html>502 Bad Gateway</html>'],
          [''],
          ['[]'],
          ['{"ok":"true"}']
        ]
      end

      with_them do
        it 'prints the response and returns zero when Slack does not accept the post', :aggregate_failures do
          stub_post_message(body: body)

          expect(notify('master-broken', message, icon_emoji, username, token: bot_token)).to eq(0)

          expect(output.string).to eq("Slack did not accept the message (HTTP 200): #{body}\n")
          expect(output.string).not_to include(bot_token)
        end
      end

      it 'includes the HTTP status when a proxy answers with an error' do
        stub_post_message(status: 429, body: '')

        notify('master-broken', message, icon_emoji, username, token: bot_token)

        expect(output.string).to eq("Slack did not accept the message (HTTP 429): \n")
      end

      it 'returns zero when the response has no body', :aggregate_failures do
        response = instance_double(Net::HTTPResponse, body: nil, code: '204')
        allow(Net::HTTP).to receive(:post).and_return(response)

        expect(notify('master-broken', message, icon_emoji, username, token: bot_token)).to eq(0)
        expect(output.string).to eq("Slack did not accept the message (HTTP 204): \n")
      end

      it 'raises when Slack cannot be reached' do
        stub_request(:post, post_message_url).to_raise(SocketError)

        expect { notify('master-broken', message, icon_emoji, username, token: bot_token) }
          .to raise_error(SocketError)
      end
    end
  end

  describe 'running the script' do
    it 'prints the usage and exits zero without CI_SLACK_WEBHOOK_URL', :aggregate_failures do
      output, status = Open3.capture2e(
        { 'CI_SLACK_WEBHOOK_URL' => nil, 'CI_SLACK_BOT_TOKEN' => nil },
        script, 'CR6QH3D7C', message, icon_emoji, username
      )

      expect(status).to be_success
      expect(output).to include('Missing argument(s) - Use: ')
    end

    it 'reads the arguments and CI_SLACK_WEBHOOK_URL and tries to post', :aggregate_failures do
      closed_port = TCPServer.open('127.0.0.1', 0) { |server| server.addr[1] }

      output, status = Open3.capture2e(
        { 'CI_SLACK_WEBHOOK_URL' => "http://127.0.0.1:#{closed_port}/webhook", 'CI_SLACK_BOT_TOKEN' => nil },
        script, 'CR6QH3D7C', message, icon_emoji, username
      )

      expect(status).not_to be_success
      expect(output).to include('Connection refused')
    end

    it 'reads CI_SLACK_BOT_TOKEN and posts with it', :aggregate_failures do
      Dir.mktmpdir do |dir|
        # Replaces the network call, so the run proves what the script would send without contacting Slack.
        preload = File.join(dir, 'preload.rb')
        File.write(preload, <<~RUBY)
          require 'net/http'
          Net::HTTP.define_singleton_method(:post) do |url, data, header|
            puts "POST \#{url} \#{header['Authorization']} \#{data}"
            Struct.new(:body, :code).new('{"ok":true}', '200')
          end
        RUBY

        output, status = Open3.capture2e(
          { 'CI_SLACK_BOT_TOKEN' => 'xoxb-from-env', 'CI_SLACK_WEBHOOK_URL' => nil },
          RbConfig.ruby, '-r', preload, script, 'master-broken', message, icon_emoji, username
        )

        expect(status).to be_success
        expect(output).to include('POST https://slack.com/api/chat.postMessage Bearer xoxb-from-env')
        expect(output).to include('channel=%23master-broken')
      end
    end
  end
end
