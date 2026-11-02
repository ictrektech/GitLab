# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:secrets_management:openbao', :silence_stdout, feature_category: :secrets_management do
  before do
    Rake.application.rake_require 'tasks/gitlab/secrets_management/openbao'
  end

  describe 'recovery_key:store' do
    subject(:task) { run_rake_task('gitlab:secrets_management:openbao:recovery_key:store') }

    let(:encoded_jwt) { "encoded_jwt.a.key" }
    let(:returned_recovery_key) { "ffffffffff38b1f97d18a63fb044015a9c776aa7f6c0e071c22bd25c062e586e" }
    let(:active_recovery_key) { SecretsManagement::RecoveryKey.active.take }
    let(:returned_keys) { [returned_recovery_key] }
    let(:recovery_response) do
      {
        "request_id" => "e1dfe66c-e97b-9ff3-acaf-3a6b24c64250",
        "lease_id" => "",
        "renewable" => false,
        "lease_duration" => 0,
        "data" => {
          "backup" => false,
          "complete" => true,
          "keys" => returned_keys,
          "keys_base64" => ["Suei4Rc4sfl9GKY/sEQBWpx3aqf2wOBxwivSXAYuWG4="],
          "n" => 1,
          "pgp_fingerprints" => nil,
          "t" => 1,
          "verification_nonce" => "",
          "verification_required" => false
        },
        "wrap_info" => nil,
        "warnings" => nil,
        "auth" => nil
      }
    end

    before do
      allow_next_instance_of(SecretsManagement::GlobalSecretsManagerJwt) do |smj|
        allow(smj).to receive(:encoded).and_return(encoded_jwt)
      end

      allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
        allow(smc).to receive(:init_rotate_recovery).and_return(recovery_response)
      end
    end

    it 'saves the returned key to database' do
      expect { task }.to change { SecretsManagement::RecoveryKey.count }

      expect(active_recovery_key.key).to eq(returned_recovery_key)
      expect(active_recovery_key.active).to be true
    end

    context 'if there already exists a RecoveryKey in the database' do
      let(:current_recovery_key) { "a" * 64 }
      let!(:old_recovery_key) { create(:sm_recovery_key, key: current_recovery_key, active: true) }

      it 'does not call the OpenBao API and does not change the stored key' do
        expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)

        expect { task }.not_to change { SecretsManagement::RecoveryKey.count }

        old_recovery_key.reload
        expect(old_recovery_key.active).to be true
      end

      it 'prints a message directing the user to recovery_key:show' do
        expect { task }.to output(
          /Recovery key already generated in OpenBao and stored in the GitLab database/
        ).to_stdout
      end
    end

    context 'when the response contains a null key' do
      let(:recovery_response) do
        {
          "request_id" => "e1dfe66c-e97b-9ff3-acaf-3a6b24c64250",
          "lease_id" => "",
          "renewable" => false,
          "lease_duration" => 0,
          "data" => {
            "backup" => false,
            "complete" => true,
            "n" => 1,
            "pgp_fingerprints" => nil,
            "t" => 1,
            "verification_nonce" => "",
            "verification_required" => false
          },
          "wrap_info" => nil,
          "warnings" => nil,
          "auth" => nil
        }
      end

      it "does not persist anything" do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          allow(smc).to receive(:init_rotate_recovery).and_return(recovery_response)
          expect(smc).to receive(:cancel_rotate_recovery)
        end

        expect { task }.not_to change { SecretsManagement::RecoveryKey.count }
      end

      it 'prints a message explaining the key cannot be retrieved via this task' do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          allow(smc).to receive(:init_rotate_recovery).and_return(recovery_response)
          allow(smc).to receive(:cancel_rotate_recovery)
        end

        expect { task }.to output(/OpenBao recovery key already generated and consumed/).to_stdout
      end
    end

    context 'when the api raises an exception' do
      let(:exception_class) { SecretsManagement::SecretsManagerClient::ApiError }

      it 'logs the exception by calling track_and_raise_exception' do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          expect(smc).to receive(:init_rotate_recovery).and_raise(exception_class)
        end

        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).and_raise(exception_class)

        expect { task }.to raise_exception(exception_class)
      end
    end
  end

  describe 'recovery_key:fetch' do
    subject(:task) { run_rake_task('gitlab:secrets_management:openbao:recovery_key:fetch') }

    let(:encoded_jwt) { "encoded_jwt.a.key" }
    let(:returned_recovery_key) { "ffffffffff38b1f97d18a63fb044015a9c776aa7f6c0e071c22bd25c062e586e" }
    let(:recovery_response) do
      {
        "data" => {
          "keys" => [returned_recovery_key]
        }
      }
    end

    context 'when the user declines with n' do
      before do
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it 'does not call the OpenBao API' do
        expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)

        task
      end

      it 'does not display the key' do
        expect { task }.not_to output(/#{returned_recovery_key}/).to_stdout
      end
    end

    context 'when the user presses enter without input' do
      before do
        allow($stdin).to receive(:gets).and_return("\n")
      end

      it 'does not call the OpenBao API' do
        expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)

        task
      end
    end

    context 'when the user confirms with y' do
      before do
        allow($stdin).to receive(:gets).and_return("y\n")

        allow_next_instance_of(SecretsManagement::GlobalSecretsManagerJwt) do |smj|
          allow(smj).to receive(:encoded).and_return(encoded_jwt)
        end

        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          allow(smc).to receive(:init_rotate_recovery).and_return(recovery_response)
        end
      end

      it 'displays the recovery key' do
        expect { task }.to output(/#{returned_recovery_key}/).to_stdout
      end

      it 'does not save the key to the database' do
        expect { task }.not_to change { SecretsManagement::RecoveryKey.count }
      end
    end

    context 'when an active recovery key is already stored in the database' do
      let!(:existing_key) { create(:sm_recovery_key, active: true) }

      it 'does not call the OpenBao API' do
        expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)

        task
      end

      it 'does not prompt for confirmation' do
        expect($stdin).not_to receive(:gets)

        task
      end

      it 'prints a helpful message' do
        expect { task }.to output(/already stored in the database/).to_stdout
      end
    end

    context 'when OpenBao returns no keys' do
      before do
        allow($stdin).to receive(:gets).and_return("y\n")

        allow_next_instance_of(SecretsManagement::GlobalSecretsManagerJwt) do |smj|
          allow(smj).to receive(:encoded).and_return(encoded_jwt)
        end
      end

      it 'cancels the rotation and does not display a key' do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          allow(smc).to receive(:init_rotate_recovery).and_return({ "data" => {} })
          expect(smc).to receive(:cancel_rotate_recovery)
        end

        expect { task }.not_to output(/#{returned_recovery_key}/).to_stdout
      end

      it 'prints a message explaining the key cannot be retrieved again' do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          allow(smc).to receive(:init_rotate_recovery).and_return({ "data" => {} })
          allow(smc).to receive(:cancel_rotate_recovery)
        end

        expect { task }.to output(/OpenBao recovery key already generated and consumed/).to_stdout
      end
    end

    context 'when the API raises an exception' do
      let(:exception_class) { SecretsManagement::SecretsManagerClient::ApiError }

      before do
        allow($stdin).to receive(:gets).and_return("y\n")

        allow_next_instance_of(SecretsManagement::GlobalSecretsManagerJwt) do |smj|
          allow(smj).to receive(:encoded).and_return(encoded_jwt)
        end
      end

      it 'logs the exception by calling track_and_raise_exception' do
        allow_next_instance_of(SecretsManagement::SecretsManagerClient) do |smc|
          expect(smc).to receive(:init_rotate_recovery).and_raise(exception_class)
        end

        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).and_raise(exception_class)

        expect { task }.to raise_exception(exception_class)
      end
    end
  end

  describe 'recovery_key:show' do
    subject(:task) { run_rake_task('gitlab:secrets_management:openbao:recovery_key:show') }

    context 'when no active recovery key exists in the database' do
      it 'prints a message and does not prompt' do
        expect($stdin).not_to receive(:gets)

        expect { task }.to output(/No recovery key found in database/).to_stdout
      end
    end

    context 'when an active recovery key exists in the database' do
      let(:stored_key) { "#{'abcdef1234' * 6}abcd" }
      let!(:recovery_key) { create(:sm_recovery_key, key: stored_key, active: true) }

      context 'when the user confirms with y' do
        before do
          allow($stdin).to receive(:gets).and_return("y\n")
        end

        it 'prints the recovery key' do
          expect { task }.to output(/#{stored_key}/).to_stdout
        end

        it 'does not call the OpenBao API' do
          expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)

          task
        end
      end

      context 'when the user declines with n' do
        before do
          allow($stdin).to receive(:gets).and_return("n\n")
        end

        it 'does not print the key' do
          expect { task }.not_to output(/#{stored_key}/).to_stdout
        end
      end

      context 'when the user presses enter without input' do
        before do
          allow($stdin).to receive(:gets).and_return("\n")
        end

        it 'does not print the key' do
          expect { task }.not_to output(/#{stored_key}/).to_stdout
        end
      end
    end
  end

  describe 'root_token:generate' do
    subject(:task) { run_rake_task('gitlab:secrets_management:openbao:root_token:generate') }

    let(:client) { instance_double(SecretsManagement::SecretsManagerClient) }
    let(:recovery_key) { "ffffffffff38b1f97d18a63fb044015a9c776aa7f6c0e071c22bd25c062e586e" }
    let(:root_token) { "s.#{'Ab1' * 8}" }
    let(:otp) { "abcdefghijklmnopqrstuvwxyz" }
    let(:encoded_token) { Base64.strict_encode64(xor(root_token, otp)).delete("=") }
    let(:status_response) { { "data" => { "started" => false, "required" => 1, "progress" => 0 } } }
    let(:init_response) { { "data" => { "started" => true, "nonce" => "the-nonce", "otp" => otp } } }
    let(:update_response) { { "data" => { "complete" => true, "encoded_token" => encoded_token } } }
    let(:confirmations) { ["y\n"] }

    before do
      allow(SecretsManagement::GlobalSecretsManagerJwt).to receive(:new)
        .and_return(instance_double(SecretsManagement::GlobalSecretsManagerJwt, encoded: "encoded_jwt"))
      allow(SecretsManagement::SecretsManagerClient).to receive(:new).and_return(client)
      allow(client).to receive_messages(
        generate_root_token_status: status_response,
        init_generate_root_token: init_response,
        update_generate_root_token: update_response,
        cancel_generate_root_token: nil
      )
      allow($stdin).to receive(:gets).and_return(*confirmations)
      allow(Gitlab::TaskHelpers).to receive(:prompt_for_password).and_return(recovery_key)
    end

    def xor(value, otp)
      value.bytes.zip(otp.bytes).map { |value_byte, otp_byte| value_byte ^ otp_byte }.pack("C*")
    end

    context 'when the user confirms and OpenBao accepts the recovery key' do
      it 'prints the decoded root token' do
        expect { task }.to output(/#{Regexp.escape(root_token)}/).to_stdout
      end

      it 'does not print the recovery key' do
        expect { task }.not_to output(/#{recovery_key}/).to_stdout
      end

      it 'submits the recovery key with the nonce of the attempt' do
        expect(client).to receive(:update_generate_root_token).with(key: recovery_key, nonce: "the-nonce")

        task
      end

      it 'does not cancel the completed attempt' do
        expect(client).not_to receive(:cancel_generate_root_token)

        task
      end

      it 'signs a new JWT for each OpenBao client' do
        task

        expect(SecretsManagement::GlobalSecretsManagerJwt).to have_received(:new).twice
      end
    end

    context 'when the user declines' do
      let(:confirmations) { ["n\n"] }

      it 'aborts without calling OpenBao or asking for the recovery key', :aggregate_failures do
        expect(SecretsManagement::SecretsManagerClient).not_to receive(:new)
        expect(Gitlab::TaskHelpers).not_to receive(:prompt_for_password)

        expect { task }.to output(/Aborted/).to_stdout
      end
    end

    context 'when OpenBao has no recovery key' do
      let(:status_response) { { "data" => { "started" => false, "required" => 0, "progress" => 0 } } }

      it 'tells the user to create one and does not start an attempt', :aggregate_failures do
        expect(client).not_to receive(:init_generate_root_token)
        expect(Gitlab::TaskHelpers).not_to receive(:prompt_for_password)

        expect { task }.to output(/OpenBao has no recovery key/).to_stdout
      end
    end

    context 'when a root token generation is already in progress' do
      let(:status_response) { { "data" => { "started" => true, "required" => 1, "progress" => 0 } } }

      context 'when the user agrees to cancel it' do
        let(:confirmations) { %W[y\n y\n] }

        it 'cancels it and generates a root token', :aggregate_failures do
          expect(client).to receive(:cancel_generate_root_token).ordered
          expect(client).to receive(:init_generate_root_token).ordered.and_return(init_response)

          expect { task }.to output(/#{Regexp.escape(root_token)}/).to_stdout
        end
      end

      context 'when the user declines to cancel it' do
        let(:confirmations) { %W[y\n n\n] }

        it 'leaves it in place and does not start an attempt', :aggregate_failures do
          expect(client).not_to receive(:cancel_generate_root_token)
          expect(client).not_to receive(:init_generate_root_token)

          expect { task }.to output(/Aborted/).to_stdout
        end
      end
    end

    context 'when an active recovery key is stored in the database' do
      let(:stored_recovery_key) { "a" * 64 }

      before do
        create(:sm_recovery_key, key: stored_recovery_key, active: true)
      end

      it 'submits the stored recovery key without asking for one', :aggregate_failures do
        expect(Gitlab::TaskHelpers).not_to receive(:prompt_for_password)
        expect(client).to receive(:update_generate_root_token).with(key: stored_recovery_key, nonce: "the-nonce")

        expect { task }.to output(/Using the recovery key stored in the GitLab database/).to_stdout
      end

      it 'does not print the stored recovery key' do
        expect { task }.not_to output(/#{stored_recovery_key}/).to_stdout
      end
    end

    context 'when only an inactive recovery key is stored in the database' do
      before do
        create(:sm_recovery_key, key: "a" * 64, active: false)
      end

      it 'asks for the recovery key' do
        expect(client).to receive(:update_generate_root_token).with(key: recovery_key, nonce: "the-nonce")

        task

        expect(Gitlab::TaskHelpers).to have_received(:prompt_for_password)
      end
    end

    context 'when no recovery key is entered' do
      let(:recovery_key) { "" }

      it 'aborts without starting an attempt' do
        expect(client).not_to receive(:init_generate_root_token)

        expect { task }.to output(/No recovery key entered/).to_stdout
      end
    end

    context 'when OpenBao rejects the recovery key' do
      let(:error) do
        SecretsManagement::SecretsManagerClient::ServiceUnavailableError.new(
          "root generation aborted: unable to authenticate: recovery key verification failed"
        )
      end

      before do
        allow(client).to receive(:update_generate_root_token).and_raise(error)
      end

      it 'cancels the attempt and raises the error', :aggregate_failures do
        expect(client).to receive(:cancel_generate_root_token)
        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).with(error).and_raise(error)

        expect { task }.to raise_error(error.class)
      end

      it 'does not print the recovery key' do
        allow(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).and_raise(error)

        expect { expect { task }.to raise_error(error.class) }.not_to output(/#{recovery_key}/).to_stdout
      end

      context 'when cancelling the attempt also fails' do
        before do
          allow(client).to receive(:cancel_generate_root_token)
            .and_raise(SecretsManagement::SecretsManagerClient::ConnectionError, "connection refused")
        end

        it 'says so and still raises the original error', :aggregate_failures do
          expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).with(error).and_raise(error)

          expect { expect { task }.to raise_error(error.class) }
            .to output(/Could not cancel the root token generation attempt/).to_stdout
        end
      end
    end

    context 'when OpenBao does not complete the attempt' do
      let(:update_response) { { "data" => { "complete" => false, "progress" => 0, "required" => 1 } } }

      it 'cancels the attempt and prints no root token', :aggregate_failures do
        expect(client).to receive(:cancel_generate_root_token)

        expect { task }.to output(/did not complete the root token generation/).to_stdout
      end
    end

    context 'when the encoded token is not valid base64' do
      let(:encoded_token) { "!!!!" }

      it 'raises a decode error' do
        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception)
          .with(an_instance_of(SecretsManagement::RakeTask::GenerateRootToken::DecodeError))
          .and_call_original

        expect { task }.to raise_error(SecretsManagement::RakeTask::GenerateRootToken::DecodeError)
      end
    end

    context 'when the encoded token does not match the OTP length' do
      let(:encoded_token) { Base64.strict_encode64("short").delete("=") }

      it 'raises a decode error' do
        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception)
          .with(an_instance_of(SecretsManagement::RakeTask::GenerateRootToken::DecodeError))
          .and_call_original

        expect { task }.to raise_error(SecretsManagement::RakeTask::GenerateRootToken::DecodeError)
      end
    end
  end
end
