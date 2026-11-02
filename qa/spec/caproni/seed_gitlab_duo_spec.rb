# frozen_string_literal: true

require_relative '../../caproni/scripts/seed_gitlab_duo'

RSpec.describe SeedGitlabDuo do
  describe '.seed_program' do
    subject(:program) { described_class.seed_program(code) }

    # Has a quote and an interpolation marker, so raw rendering fails here
    let(:code) { %(code"\#{system("id")}) }

    it 'renders the activation code as an escaped literal rather than interpolating it raw' do
      expect(program).to include("ActivateService.new.execute(#{code.inspect})")
      expect(program).not_to include(%(execute("#{code}")))
    end

    it 'skips activation when a cloud license is already active, so a re-run is a no-op' do
      expect(program).to include('License.current&.cloud_license?')
    end

    it 'is valid Ruby' do
      expect { RubyVM::InstructionSequence.compile(program) }.not_to raise_error
    end
  end
end
