# frozen_string_literal: true

require 'rubocop_spec_helper'
require_relative '../../rubocop/domain_paths'

RSpec.describe RuboCop::DomainPaths, feature_category: :tooling do
  let(:cop_class) do
    Class.new(RuboCop::Cop::Base) do
      def self.badge
        RuboCop::Cop::Badge.parse('Test/DomainPathsCop')
      end
    end
  end

  let(:root) { File.expand_path('../..', __dir__) }
  let(:cop_config) do
    { 'Include' => ['app/workers/**/*'], 'Exclude' => ['app/workers/legacy/**/*', 'app/workers/old.rb'] }
  end

  let(:config) { RuboCop::Config.new({ 'Test/DomainPathsCop' => cop_config }, File.join(root, '.rubocop.yml')) }
  let(:cop) { cop_class.new(config) }

  def relevant?(path)
    cop.relevant_file?(File.join(root, path))
  end

  it 'applies an Include glob to the top-level path' do
    expect(relevant?('app/workers/foo_worker.rb')).to be(true)
  end

  it 'applies an Include glob to the equivalent domain path' do
    expect(relevant?('domains/cd/app/workers/foo_worker.rb')).to be(true)
  end

  it 'does not apply an Include glob to an unrelated domain path' do
    expect(relevant?('domains/cd/app/models/foo.rb')).to be(false)
  end

  it 'does not map a domains/ directory below the root' do
    expect(relevant?('lib/domains/cd/app/workers/foo_worker.rb')).to be(false)
  end

  it 'applies an Exclude glob to the equivalent domain path' do
    expect(relevant?('domains/cd/app/workers/legacy/foo_worker.rb')).to be(false)
  end

  it 'does not apply a literal Exclude path to the equivalent domain path' do
    expect(relevant?('domains/cd/app/workers/old.rb')).to be(true)
  end

  context 'with an EE-scoped glob' do
    let(:cop_config) { { 'Include' => ['ee/app/workers/**/*'] } }

    it 'applies it to the EE half of a domain' do
      expect(relevant?('domains/cd/ee/app/workers/foo_worker.rb')).to be(true)
    end

    it 'does not apply it to the CE half of a domain' do
      expect(relevant?('domains/cd/app/workers/foo_worker.rb')).to be(false)
    end
  end
end
