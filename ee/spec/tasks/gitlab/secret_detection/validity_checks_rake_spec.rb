# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:secret_detection:validity_checks tasks', :silence_stdout, feature_category: :secret_detection do
  before do
    Rake.application.rake_require 'tasks/gitlab/secret_detection/validity_checks'
  end

  # The task writes to repo-relative paths, so every example runs chdir'd into
  # a tmpdir with the expected directory structure pre-created.
  around do |example|
    Dir.mktmpdir do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, 'ee/lib/security/secret_detection/partner_tokens'))
      FileUtils.mkdir_p(File.join(tmpdir, 'ee/spec/lib/security/secret_detection/partner_tokens'))
      Dir.chdir(tmpdir) { example.run }
    end
  end

  let(:valid_attrs) do
    {
      'token_type' => 'Acme API token',
      'class_name' => 'AcmeClient',
      'endpoint' => 'https://api.acme.dev/v1/whoami',
      'auth_style' => 'bearer',
      'token_pattern' => '\Aacme_[a-z0-9]{20}\z',
      'sample_token' => "acme_#{'a' * 20}",
      'status_map' => { '200' => 'active', '401' => 'inactive' },
      'rate_limit_key' => 'partner_acme_api'
    }
  end

  let(:client_path) { 'ee/lib/security/secret_detection/partner_tokens/acme_client.rb' }
  let(:client_spec_path) { 'ee/spec/lib/security/secret_detection/partner_tokens/acme_client_spec.rb' }

  def write_vendor_yaml(name, attrs)
    File.write(name, attrs.to_yaml)
    name
  end

  describe 'validity_checks:generate' do
    subject(:run_task) { run_rake_task('gitlab:secret_detection:validity_checks:generate', spec_path) }

    let(:spec_path) { write_vendor_yaml('acme.yml', valid_attrs) }

    before do
      allow(Open3).to receive(:capture2e)
        .and_return(['', instance_double(Process::Status, success?: true)])
    end

    it 'writes the generated verifier and spec', :aggregate_failures do
      run_task

      expect(File.read(client_path)).to include('class AcmeClient < BaseClient')
      expect(File.read(client_spec_path)).to include(
        'RSpec.describe Security::SecretDetection::PartnerTokens::AcmeClient'
      )
    end

    it 'raises without a spec path' do
      expect { run_rake_task('gitlab:secret_detection:validity_checks:generate') }
        .to raise_error(/Provide a vendor definition YAML/)
    end

    context 'with a directory containing no definition YAMLs' do
      let(:spec_path) do
        FileUtils.mkdir_p('empty')
        'empty'
      end

      it 'raises' do
        expect { run_task }.to raise_error(/No vendor definition YAMLs found/)
      end
    end

    context 'when a definition in the batch is invalid' do
      let(:spec_path) do
        write_vendor_yaml('broad.yml', valid_attrs.merge('token_pattern' => '\A[a-z]{4}\z', 'sample_token' => 'aaaa'))
      end

      it 'raises and writes nothing', :aggregate_failures do
        expect { run_task }.to raise_error(
          Security::SecretDetection::PartnerTokens::Generator::VendorDefinition::InvalidDefinitionError,
          /too broad/
        )
        expect(File.exist?(client_path)).to be(false)
      end
    end

    context 'when a generated file already exists' do
      before do
        File.write(client_path, 'existing content')
      end

      it 'refuses to overwrite without FORCE' do
        expect { run_task }.to raise_error(/Refusing to overwrite/)
      end

      it 'overwrites when FORCE=true' do
        stub_env('FORCE', 'true')

        run_task

        expect(File.read(client_path)).to include('class AcmeClient < BaseClient')
      end
    end

    context 'when rubocop autocorrect does not run cleanly' do
      before do
        allow(Open3).to receive(:capture2e)
          .and_return(["some rubocop diagnostic\n", instance_double(Process::Status, success?: false)])
      end

      it 'still writes the files and surfaces the rubocop output in the warning', :aggregate_failures do
        expect { run_task }.to output(/did not run cleanly.*some rubocop diagnostic/m).to_stderr

        expect(File.read(client_path)).to include('class AcmeClient < BaseClient')
      end
    end

    context 'when two specs in the batch generate the same file' do
      # Distinct class names, same underscored path: both write ab_client.rb.
      let(:spec_path) { '.' }

      before do
        write_vendor_yaml('a.yml', valid_attrs.merge('class_name' => 'AbClient', 'token_type' => 'Acme A token'))
        write_vendor_yaml('b.yml', valid_attrs.merge('class_name' => 'ABClient', 'token_type' => 'Acme B token'))
      end

      it 'raises instead of silently overwriting the first vendor', :aggregate_failures do
        expect { run_task }.to raise_error(/generate the same file/)
        expect(Dir.glob('ee/lib/security/secret_detection/partner_tokens/*.rb')).to be_empty
      end
    end
  end

  describe 'validity_checks:preview' do
    it 'prints the generated verifier without writing files', :aggregate_failures do
      spec_path = write_vendor_yaml('acme.yml', valid_attrs)

      expect { run_rake_task('gitlab:secret_detection:validity_checks:preview', spec_path) }
        .to output(/class AcmeClient < BaseClient/).to_stdout

      expect(File.exist?(client_path)).to be(false)
    end
  end
end
