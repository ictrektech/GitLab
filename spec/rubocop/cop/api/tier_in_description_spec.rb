# frozen_string_literal: true

require 'rubocop_spec_helper'
require_relative '../../../../rubocop/cop/api/tier_in_description'

RSpec.describe RuboCop::Cop::API::TierInDescription, :config, feature_category: :api do
  let(:msg) { 'Do not use tier terms (Premium, Ultimate, EE-only, requires a license) in API descriptions. [...]' }

  context 'when detail contains tier terms' do
    where(:detail) do
      [
        'Available in Premium and Ultimate.',
        'Ultimate only.',
        'Available in GitLab Starter.',
        'Available on Bronze, Silver, and Gold plans.',
        'This is an EE-only endpoint.',
        'This is an EE only endpoint.',
        'Available in GitLab EE.',
        'Requires a valid license.',
        'Requires an active subscription.',
        'AVAILABLE IN PREMIUM.'
      ]
    end

    with_them do
      it 'registers an offense' do
        expect_offense(<<~RUBY, detail: detail)
          desc 'Get all widgets' do
            detail '%{detail}'
                   ^^{detail}^ #{msg}
            tags %w[widgets]
          end
        RUBY
      end
    end

    it 'registers an offense for concatenated detail string' do
      expect_offense(<<~RUBY)
        desc 'Get all widgets' do
          detail 'Gets all widgets. ' \\
                 ^^^^^^^^^^^^^^^^^^^^^^ #{msg}
            'Filtering is only supported in the Premium tier and above.'
          tags %w[widgets]
        end
      RUBY
    end

    it 'registers an offense when detail is the only statement in the block' do
      expect_offense(<<~RUBY)
        desc 'Get all widgets' do
          detail 'Ultimate only.'
                 ^^^^^^^^^^^^^^^^ #{msg}
        end
      RUBY
    end
  end

  context 'when desc summary contains tier terms' do
    it 'registers an offense' do
      expect_offense(<<~RUBY)
        desc 'Get all widgets (Premium and above)' do
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{msg}
          detail 'Gets all widgets.'
          tags %w[widgets]
        end
      RUBY
    end

    it 'registers an offense for interpolation with tier terms' do
      expect_offense(<<~'RUBY', msg: msg)
        desc "Get all #{resource} widgets (Ultimate only)" do
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ %{msg}
          detail 'Gets all widgets.'
          tags %w[widgets]
        end
      RUBY
    end
  end

  context 'when both summary and detail contain tier terms' do
    it 'registers offenses for both' do
      expect_offense(<<~RUBY)
        desc 'Get all epics (Premium and above)' do
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{msg}
          detail 'Requires a Premium subscription.'
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ #{msg}
          tags %w[epics]
        end
      RUBY
    end
  end

  context 'when desc block does not contain tier terms' do
    it 'does not register an offense with route_setting tier' do
      expect_no_offenses(<<~RUBY)
        route_setting :tier, :premium
        desc 'Get all epics' do
          detail 'Gets all epics of the requested group and its subgroups.'
          tags %w[epics]
        end
      RUBY
    end

    it 'does not register an offense for words that only contain a tier term' do
      expect_no_offenses(<<~RUBY)
        desc 'Get golden widgets' do
          detail 'Lists the license templates and the starter_kit widgets.'
          tags %w[widgets]
        end
      RUBY
    end
  end

  context 'when a non-desc block is used' do
    it 'does not register an offense' do
      expect_no_offenses(<<~RUBY)
        params do
          requires :id, type: String, desc: 'Premium and Ultimate only.'
        end
      RUBY
    end
  end

  context 'when desc is called without a block' do
    it 'does not register an offense' do
      expect_no_offenses(<<~RUBY)
        desc 'Premium and Ultimate only'
      RUBY
    end
  end

  context 'when desc is called on an object' do
    it 'does not register an offense' do
      expect_no_offenses(<<~RUBY)
        object.desc 'Premium and Ultimate only' do
          detail 'Premium and Ultimate only.'
        end
      RUBY
    end
  end
end
