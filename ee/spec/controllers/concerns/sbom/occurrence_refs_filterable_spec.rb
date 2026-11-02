# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sbom::OccurrenceRefsFilterable, feature_category: :dependency_management do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:developer) { create(:user, developer_of: group) }
  let_it_be(:guest) { create(:user, guest_of: group) }

  let(:consumer_class) do
    filterable = described_class

    Class.new do
      include filterable

      attr_reader :current_user, :filterable_namespace

      def initialize(current_user, filterable_namespace)
        @current_user = current_user
        @filterable_namespace = filterable_namespace
      end

      public :use_elasticsearch?, :requested_advanced_filters, :advanced_filters_available?,
        :filter_available?, :validate_advanced_filters!
    end
  end

  let(:user) { developer }

  subject(:consumer) { consumer_class.new(user, group) }

  before do
    stub_licensed_features(dependency_scanning: true)
    allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
      .to receive(:advanced_dependency_management_allowed?).and_return(true)
  end

  describe '#requested_advanced_filters' do
    it 'includes malware in either state', :aggregate_failures do
      expect(consumer.requested_advanced_filters(malware: true)).to contain_exactly(:malware)
      expect(consumer.requested_advanced_filters(malware: false)).to contain_exactly(:malware)
    end

    it 'includes an explicit null, which graphql-ruby keeps as an argument key' do
      expect(consumer.requested_advanced_filters(malware: nil)).to contain_exactly(:malware)
    end

    it 'includes the tracked-ref filters', :aggregate_failures do
      expect(consumer.requested_advanced_filters(security_project_tracked_context_id: [1]))
        .to contain_exactly(:security_project_tracked_context_id)
      expect(consumer.requested_advanced_filters(tracked_refs_scope: :all_refs))
        .to contain_exactly(:tracked_refs_scope)
    end

    it 'includes the string a REST caller sends' do
      filters = ActionController::Parameters.new(malware: 'false').permit(:malware)

      expect(consumer.requested_advanced_filters(filters)).to contain_exactly(:malware)
    end

    it 'is empty when no advanced filter was asked for', :aggregate_failures do
      expect(consumer.requested_advanced_filters({})).to be_empty
      expect(consumer.requested_advanced_filters(component_names: %w[actionpack])).to be_empty
    end
  end

  describe '#advanced_filters_available?' do
    where(:user, :available) do
      ref(:developer) | true
      ref(:guest)     | false
      nil             | false
    end

    with_them do
      it { expect(consumer.advanced_filters_available?).to be(available) }
    end

    # Readiness reaches the concern through the ability, not a direct call:
    # Sbom::AdvancedDependencyManagementPolicy prevents it when the index cannot serve reads.
    it 'is false when the Elasticsearch index is not ready for reads' do
      allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
        .to receive(:advanced_dependency_management_allowed?).and_return(false)

      expect(consumer.advanced_filters_available?).to be(false)
    end
  end

  describe '#filter_available?' do
    it 'is true for every advanced filter when the flags are on', :aggregate_failures do
      described_class::ADVANCED_FILTERS.each do |filter|
        expect(consumer.filter_available?(filter)).to be(true)
      end
    end

    it 'gates malware separately from the tracked-ref filters', :aggregate_failures do
      stub_feature_flags(project_dependency_tracked_ref: false)

      expect(consumer.filter_available?(:malware)).to be(true)
      expect(consumer.filter_available?(:tracked_refs_scope)).to be(false)
    end

    # The ability is asked once for the whole set, so this answers on the flag alone.
    it 'does not consider the ability' do
      expect(consumer_class.new(guest, group).filter_available?(:malware)).to be(true)
    end

    # Guards the fallback: a filter added to ADVANCED_FILTERS without a flag mapped to it has to
    # come back unavailable, not inherit whichever flag happens to be last in the case.
    it 'is false for a filter with no flag mapped to it' do
      expect(consumer.filter_available?(:bogus)).to be(false)
    end
  end

  describe '#validate_advanced_filters!' do
    it 'passes when no advanced filter was asked for', :aggregate_failures do
      expect { consumer.validate_advanced_filters!({}) }.not_to raise_error
      expect { consumer.validate_advanced_filters!(component_names: %w[actionpack]) }.not_to raise_error
    end

    it 'passes when the filter is available' do
      expect { consumer.validate_advanced_filters!(malware: true) }.not_to raise_error
    end

    context 'when the filter is unavailable' do
      before do
        allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
          .to receive(:advanced_dependency_management_allowed?).and_return(false)
      end

      it 'raises rather than falling back to an unfiltered list', :aggregate_failures do
        [true, false, nil].each do |value|
          expect { consumer.validate_advanced_filters!(malware: value) }
            .to raise_error(::Gitlab::Graphql::Errors::ArgumentError, 'The malware filter is not available.')
        end
      end

      it 'raises for a user without the ability' do
        consumer = consumer_class.new(guest, group)

        expect { consumer.validate_advanced_filters!(malware: true) }
          .to raise_error(::Gitlab::Graphql::Errors::ArgumentError)
      end

      # Denying the ability makes every requested filter unavailable at once, so the message has
      # to agree in number. validate_malware_tracked_refs_conflict! allows this pairing when the
      # tracked ref is the default branch.
      it 'pluralises when more than one filter is unavailable' do
        filters = { malware: true, security_project_tracked_context_id: [1] }

        expect { consumer.validate_advanced_filters!(filters) }
          .to raise_error(::Gitlab::Graphql::Errors::ArgumentError,
            'The malware and tracked_ref_ids filters are not available.')
      end
    end

    context 'when the tracked-ref filters are unavailable' do
      before do
        stub_feature_flags(project_dependency_tracked_ref: false)
      end

      it 'names the argument the caller passed rather than the internal one' do
        expect { consumer.validate_advanced_filters!(security_project_tracked_context_id: [1]) }
          .to raise_error(::Gitlab::Graphql::Errors::ArgumentError,
            'The tracked_ref_ids filter is not available.')
      end

      it 'raises for tracked_refs_scope' do
        expect { consumer.validate_advanced_filters!(tracked_refs_scope: :all_refs) }
          .to raise_error(::Gitlab::Graphql::Errors::ArgumentError,
            'The tracked_refs_scope filter is not available.')
      end

      it 'names only the unavailable filter when an available one accompanies it' do
        expect { consumer.validate_advanced_filters!(malware: true, tracked_refs_scope: :all_refs) }
          .to raise_error(::Gitlab::Graphql::Errors::ArgumentError,
            'The tracked_refs_scope filter is not available.')
      end
    end

    it 'passes when a tracked-ref filter is available' do
      expect { consumer.validate_advanced_filters!(tracked_refs_scope: :all_refs) }.not_to raise_error
    end

    context 'when policy_violations is combined with an advanced filter' do
      let(:filters) { { malware: true, policy_violations: [:dismissed_in_mr] } }

      it 'raises rather than dropping one of the two filters' do
        expect { consumer.validate_advanced_filters!(filters) }.to raise_error(
          ::Gitlab::Graphql::Errors::ArgumentError,
          'The policy_violations filter cannot be combined with the malware filter.'
        )
      end

      # Whether the index can serve the request does not change that the pair is unanswerable,
      # so the caller gets the same error either way.
      it 'raises even when the advanced filter is unavailable' do
        allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
          .to receive(:advanced_dependency_management_allowed?).and_return(false)

        expect { consumer.validate_advanced_filters!(filters) }.to raise_error(
          ::Gitlab::Graphql::Errors::ArgumentError,
          'The policy_violations filter cannot be combined with the malware filter.'
        )
      end

      it 'passes when no advanced filter accompanies it' do
        expect { consumer.validate_advanced_filters!(policy_violations: [:dismissed_in_mr]) }
          .not_to raise_error
      end

      it 'names the tracked-ref argument the caller passed' do
        filters = { security_project_tracked_context_id: [1], policy_violations: [:dismissed_in_mr] }

        expect { consumer.validate_advanced_filters!(filters) }.to raise_error(
          ::Gitlab::Graphql::Errors::ArgumentError,
          'The policy_violations filter cannot be combined with the tracked_ref_ids filter.'
        )
      end
    end
  end

  describe '#use_elasticsearch?' do
    it 'is true only when an advanced filter was asked for and is available', :aggregate_failures do
      expect(consumer.use_elasticsearch?(malware: true)).to be(true)
      expect(consumer.use_elasticsearch?({})).to be(false)
    end

    it 'routes a tracked-ref request on its own', :aggregate_failures do
      expect(consumer.use_elasticsearch?(security_project_tracked_context_id: [1])).to be(true)
      expect(consumer.use_elasticsearch?(tracked_refs_scope: :all_refs)).to be(true)
    end

    it 'is false when the filter is unavailable' do
      allow(::Search::Elastic::SbomOccurrenceRefIndexHelper)
        .to receive(:advanced_dependency_management_allowed?).and_return(false)

      expect(consumer.use_elasticsearch?(malware: true)).to be(false)
    end

    it 'is false when the tracked-ref filters are unavailable' do
      stub_feature_flags(project_dependency_tracked_ref: false)

      expect(consumer.use_elasticsearch?(tracked_refs_scope: :all_refs)).to be(false)
    end

    # Elasticsearch has to answer the whole request or none of it, so one unavailable filter
    # cannot be dropped while the rest is served.
    it 'is false when only some of the requested filters are available' do
      stub_feature_flags(project_dependency_tracked_ref: false)

      expect(consumer.use_elasticsearch?(malware: true, tracked_refs_scope: :all_refs)).to be(false)
    end

    it 'asks whether the backend is available once however many filters were requested' do
      expect(consumer).to receive(:advanced_filters_available?).once.and_call_original

      consumer.use_elasticsearch?(
        malware: true, tracked_refs_scope: :all_refs, security_project_tracked_context_id: [1]
      )
    end
  end

  describe '#filterable_namespace' do
    let(:incomplete_consumer_class) do
      filterable = described_class

      Class.new do
        include filterable

        def current_user; end

        public :filter_available?
      end
    end

    it 'tells an including class it has to supply one' do
      expect { incomplete_consumer_class.new.filter_available?(:tracked_refs_scope) }
        .to raise_error(NotImplementedError, /must implement #filterable_namespace/)
    end
  end
end
