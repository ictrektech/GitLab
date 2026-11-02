# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Ci::PipelineAnalyticsResolver, :click_house, feature_category: :fleet_visibility do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:public_project) { create(:project, :public) }
  let_it_be(:project, freeze: false) { create(:project, :private, group: group) }
  let_it_be(:guest) { create(:user, guest_of: [project, public_project, group]) }
  let_it_be(:reporter) { create(:user, reporter_of: [project, public_project, group]) }

  let(:current_user) { reporter }
  let(:lookahead) { positive_lookahead }

  before do
    allow(lookahead).to receive(:arguments).and_return({ period: :day })
  end

  specify do
    expect(described_class).to have_nullable_graphql_type(::Types::Ci::AnalyticsType)
  end

  specify do
    expect(described_class.extras).to include(:lookahead)
  end

  shared_examples 'returns the pipeline analytics for a given container' do
    it 'loads all fields' do
      expected_fields = [:aggregate, :time_series]
      expected_fields.concat(legacy_fields)

      result = resolve_statistics(container, {})
      expect(result.keys).to match_array(expected_fields)
    end

    context 'with negative lookahead' do
      let(:lookahead) { negative_lookahead }

      it 'does not load fields that execute queries' do
        result = resolve_statistics(container, {})
        expect(result.keys).to be_empty
      end
    end
  end

  shared_examples 'it returns nils' do
    it do # # rubocop:disable RSpec/ExampleWithoutDescription -- Shared examples title is self explanatory
      result = resolve_statistics(project, {})

      expect(result).to be_nil
    end
  end

  def resolve_statistics(container, args)
    ctx = { current_user: current_user }

    resolve(described_class, obj: container, args: args, ctx: ctx, lookahead: lookahead, arg_style: :internal)
  end

  describe '#resolve' do
    context 'when container is a project' do
      let_it_be(:container) { project }

      let(:legacy_fields) do
        [
          :week_pipelines_labels,
          :week_pipelines_totals,
          :week_pipelines_successful,
          :month_pipelines_labels,
          :month_pipelines_totals,
          :month_pipelines_successful,
          :year_pipelines_labels,
          :year_pipelines_totals,
          :year_pipelines_successful,
          :pipeline_times_labels,
          :pipeline_times_values
        ]
      end

      it_behaves_like 'returns the pipeline analytics for a given container'

      context 'when the user does not have access to the CI/CD analytics data' do
        let(:current_user) { guest }

        it_behaves_like 'it returns nils'
      end

      context 'when the project is public' do
        let(:container) { public_project }

        context 'when public pipelines are disabled' do
          before do
            project.update!(public_builds: false)
          end

          context 'when user is not a member' do
            let(:current_user) { create(:user) }

            it_behaves_like 'it returns nils'
          end

          context 'when user is a guest' do
            let(:current_user) { guest }

            it_behaves_like 'it returns nils'
          end

          context 'when user is a reporter or above' do
            let(:current_user) { reporter }

            it_behaves_like 'returns the pipeline analytics for a given container'
          end
        end

        context 'when public pipelines are enabled' do
          before do
            project.update!(public_builds: true)
          end

          context 'when user is anonymous' do
            let(:current_user) { nil }

            it_behaves_like 'returns the pipeline analytics for a given container'
          end

          context 'when user is not a member' do
            let(:current_user) { create(:user) }

            it_behaves_like 'returns the pipeline analytics for a given container'
          end
        end
      end
    end

    context 'when container is a group' do
      let_it_be(:container) { group }

      let(:legacy_fields) { [] } # Legacy fields are not exposed for groups

      it_behaves_like 'returns the pipeline analytics for a given container'

      context 'with subgroup_full_paths argument' do
        let_it_be(:subgroup1, freeze: true) { create(:group, parent: group) }
        let_it_be(:subgroup2, freeze: true) { create(:group, parent: group) }

        it 'passes subgroup_full_paths to services' do
          paths = [subgroup1.full_path, subgroup2.full_path]

          expect(::Ci::CollectAggregatePipelineAnalyticsService).to receive(:new)
            .with(hash_including(subgroup_full_paths: paths))
            .and_call_original

          resolve_statistics(container, { subgroup_full_paths: paths })
        end

        it 'passes nil subgroup_full_paths when not provided' do
          expect(::Ci::CollectAggregatePipelineAnalyticsService).to receive(:new)
            .with(hash_including(subgroup_full_paths: nil))
            .and_call_original

          resolve_statistics(container, {})
        end

        it 'configures length validation on subgroup_full_paths' do
          argument = described_class.arguments['subgroupFullPaths']
          validator = argument.instance_variable_get(:@own_validators).first

          expect(validator).to be_a(GraphQL::Schema::Validator::LengthValidator)
          expect(validator.instance_variable_get(:@maximum)).to eq(described_class::MAX_SUBGROUP_PATHS)
        end
      end
    end

    context 'with name_search argument' do
      let_it_be(:container) { project }

      it 'passes name_search to both analytics services' do
        expect(::Ci::CollectAggregatePipelineAnalyticsService).to receive(:new)
          .with(hash_including(name_search: 'tier-1'))
          .and_call_original
        expect(::Ci::CollectTimeSeriesPipelineAnalyticsService).to receive(:new)
          .with(hash_including(name_search: 'tier-1'))
          .and_call_original

        resolve_statistics(container, { name_search: 'tier-1' })
      end

      it 'passes nil name_search when not provided' do
        expect(::Ci::CollectAggregatePipelineAnalyticsService).to receive(:new)
          .with(hash_including(name_search: nil))
          .and_call_original

        resolve_statistics(container, {})
      end

      it 'configures length validation on name_search' do
        argument = described_class.arguments['nameSearch']
        validator = argument.instance_variable_get(:@own_validators).first

        expect(validator).to be_a(GraphQL::Schema::Validator::LengthValidator)
        expect(validator.instance_variable_get(:@maximum)).to eq(::Ci::PipelineMetadata::NAME_MAX_LENGTH)
      end

      context 'when pipeline_analytics_siphon is disabled' do
        before do
          stub_feature_flags(pipeline_analytics_siphon: false)
        end

        it 'raises an argument error before resolving any field' do
          expect(::Ci::CollectAggregatePipelineAnalyticsService).not_to receive(:new)
          expect(Gitlab::Ci::Charts::WeekChart).not_to receive(:new)

          expect_graphql_error_to_be_created(
            Gitlab::Graphql::Errors::ArgumentError, /requires the `pipeline_analytics_siphon` feature flag/
          ) do
            resolve_statistics(container, { name_search: 'tier-1' })
          end
        end

        it 'resolves normally when name_search is blank' do
          expect(resolve_statistics(container, { name_search: '' }).keys).to include(:aggregate, :time_series)
        end
      end
    end
  end
end
