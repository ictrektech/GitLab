# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::Administration::AgentPlatformWebsocketCheck, feature_category: :"self-hosted_models" do
  let_it_be(:user) { create(:user) }

  let(:base_url) { 'http://gitlab.example.com' }
  let(:ws_url) { 'http://gitlab.example.com/api/v4/ai/duo_workflows/ws' }
  let(:token) { 'test-token' }
  let(:response_lines) { ["HTTP/1.1 101 Switching Protocols\r\n", "Upgrade: websocket\r\n", "\r\n"] }
  let(:socket) { instance_double(TCPSocket, write: nil, close: nil, wait_readable: true) }

  let(:oauth_token) { instance_double(OauthAccessToken, plaintext_token: token) }
  let(:context_service) { instance_double(Ai::DuoWorkflows::WorkflowContextGenerationService) }

  subject(:result) { described_class.new(user).execute }

  before do
    stub_config_setting(url: base_url)

    allow(Ai::DuoWorkflows::WorkflowContextGenerationService).to receive(:new).and_return(context_service)
    allow(context_service).to receive(:generate_oauth_token)
      .and_return(ServiceResponse.success(payload: { oauth_access_token: oauth_token }))

    allow(Socket).to receive(:tcp).and_return(socket)
    allow(socket).to receive(:gets).and_return(*response_lines)
  end

  describe '#execute' do
    context 'when the upgrade handshake succeeds' do
      it 'returns an ok result with the parsed status and headers', :aggregate_failures do
        expect(result).to have_attributes(
          status: :ok,
          http_status: 101,
          url: ws_url,
          headers: { 'Upgrade' => 'websocket' }
        )
        expect(result.ok?).to be(true)
        expect(result.response_time_ms).to be_a(Numeric)
      end

      it 'opens the connection with its connect timeout' do
        result

        expect(Socket).to have_received(:tcp).with('gitlab.example.com', 80, connect_timeout: 15)
      end

      it 'sends an authenticated WebSocket upgrade handshake' do
        result

        expect(socket).to have_received(:write).with(
          a_string_including('Upgrade: websocket', 'Connection: Upgrade', "Authorization: Bearer #{token}")
        )
      end

      it 'omits the default port from Host and matches Origin to it' do
        result

        expect(socket).to have_received(:write).with(
          a_string_including("Host: gitlab.example.com\r\n", "Origin: http://gitlab.example.com\r\n")
        )
      end

      context 'with an explicit port in the instance URL' do
        let(:base_url) { 'http://gitlab.example.com:8080' }

        it 'keeps the port in both Host and Origin' do
          result

          expect(socket).to have_received(:write).with(
            a_string_including("Host: gitlab.example.com:8080\r\n", "Origin: http://gitlab.example.com:8080\r\n")
          )
        end
      end
    end

    context 'when the endpoint rejects the connection' do
      let(:response_lines) { ["HTTP/1.1 403 Forbidden\r\n", "\r\n"] }

      it 'classifies the result as rejected' do
        expect(result).to have_attributes(status: :rejected, http_status: 403)
      end
    end

    context 'when the connection is not upgraded' do
      let(:response_lines) { ["HTTP/1.1 200 OK\r\n", "\r\n"] }

      it 'classifies the result as not upgraded' do
        expect(result).to have_attributes(status: :not_upgraded, http_status: 200)
      end
    end

    context 'with an HTTPS instance URL' do
      let(:base_url) { 'https://gitlab.example.com' }
      let(:ws_url) { 'https://gitlab.example.com/api/v4/ai/duo_workflows/ws' }
      let(:ssl_socket) { instance_double(OpenSSL::SSL::SSLSocket, write: nil, close: nil, wait_readable: true) }

      before do
        allow(OpenSSL::SSL::SSLSocket).to receive(:new).and_return(ssl_socket)
        allow(ssl_socket).to receive(:hostname=)
        allow(ssl_socket).to receive(:sync_close=)
        allow(ssl_socket).to receive(:post_connection_check)
        allow(ssl_socket).to receive(:gets).and_return(*response_lines)
        allow(Gitlab::X509::Certificate).to receive_messages(ca_certs_bundle: '', load_ca_certs_bundle: [])
      end

      context 'when the certificate is trusted' do
        before do
          allow(ssl_socket).to receive(:connect).and_return(ssl_socket)
        end

        it 'verifies the certificate against the CA store and the hostname', :aggregate_failures do
          result

          expect(OpenSSL::SSL::SSLSocket).to have_received(:new).with(
            socket,
            having_attributes(verify_mode: OpenSSL::SSL::VERIFY_PEER, cert_store: an_instance_of(OpenSSL::X509::Store))
          )
          expect(ssl_socket).to have_received(:post_connection_check).with('gitlab.example.com')
        end

        it 'verifies the certificate and returns an ok result' do
          expect(result).to have_attributes(status: :ok, tls_verified: true)
        end

        it 'omits port 443 from Host and Origin' do
          result

          expect(ssl_socket).to have_received(:write).with(
            a_string_including("Host: gitlab.example.com\r\n", "Origin: https://gitlab.example.com\r\n")
          )
        end
      end

      context 'when the certificate is not trusted' do
        before do
          call_count = 0
          allow(ssl_socket).to receive(:connect) do
            call_count += 1
            raise OpenSSL::SSL::SSLError, 'certificate verify failed' if call_count == 1

            ssl_socket
          end
        end

        it 'falls back to an unverified connection and records it', :aggregate_failures do
          expect(result).to have_attributes(status: :ok, tls_verified: false)
          expect(ssl_socket).not_to have_received(:post_connection_check)
        end

        it 'closes the connection that failed verification' do
          result

          expect(socket).to have_received(:close)
        end
      end

      context 'when the certificate is issued for another host' do
        before do
          allow(ssl_socket).to receive(:connect).and_return(ssl_socket)
          allow(ssl_socket).to receive(:post_connection_check)
            .and_raise(OpenSSL::SSL::SSLError, 'hostname "gitlab.example.com" does not match the server certificate')
        end

        it 'returns an error result instead of a verified one', :aggregate_failures do
          expect(result).to have_attributes(status: :error, tls_verified: nil)
          expect(result.error.message).to include('does not match the server certificate')
          expect(ssl_socket).to have_received(:close)
        end
      end

      context 'with certificates in the GitLab CA bundle' do
        include SmimeHelper

        let_it_be(:ca) { generate_root }
        let_it_be(:server_cert) { generate_cert(signer_ca: ca)[:cert] }
        let_it_be(:rejected_cert) { generate_root[:cert] }

        before do
          allow(ssl_socket).to receive(:connect).and_return(ssl_socket)
          allow(Gitlab::X509::Certificate).to receive(:load_ca_certs_bundle).and_return([rejected_cert, ca[:cert]])
          allow_next_instance_of(OpenSSL::X509::Store) do |store|
            allow(store).to receive(:add_cert).and_call_original
            allow(store).to receive(:add_cert).with(rejected_cert).and_raise(OpenSSL::X509::StoreError)
          end
        end

        it 'trusts the bundle, skipping a certificate the store rejects' do
          result

          expect(OpenSSL::SSL::SSLSocket).to have_received(:new)
            .with(socket, satisfy { |context| context.cert_store&.verify(server_cert) })
        end
      end

      context 'when the TLS handshake fails for a reason other than the certificate' do
        before do
          allow(ssl_socket).to receive(:connect)
            .and_raise(OpenSSL::SSL::SSLError, 'SSL_connect returned=1 errno=0 state=error: wrong version number')
        end

        it 'returns an error result without retrying unverified', :aggregate_failures do
          expect(result).to have_attributes(status: :error, tls_verified: nil)
          expect(result.error.message).to include('wrong version number')
          expect(OpenSSL::SSL::SSLSocket).to have_received(:new).once
        end
      end
    end

    context 'when the socket cannot connect' do
      before do
        allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED.new('Connection refused'))
      end

      it 'returns an error result capturing the exception', :aggregate_failures do
        expect(result.status).to eq(:error)
        expect(result.error).to be_a(Errno::ECONNREFUSED)
        expect(result.ok?).to be(false)
      end
    end

    context 'when the server does not respond before the read timeout' do
      before do
        allow(socket).to receive(:wait_readable).and_return(false)
      end

      it 'returns an error result indicating a timeout' do
        expect(result.status).to eq(:error)
        expect(result.error).to be_a(Timeout::Error)
      end
    end

    context 'when the token cannot be generated' do
      before do
        allow(context_service).to receive(:generate_oauth_token)
          .and_return(ServiceResponse.error(message: 'no seat'))
      end

      it 'returns an error result and never opens a socket', :aggregate_failures do
        expect(result.status).to eq(:error)
        expect(result.error.message).to eq('no seat')
        expect(Socket).not_to have_received(:tcp)
      end
    end
  end
end
