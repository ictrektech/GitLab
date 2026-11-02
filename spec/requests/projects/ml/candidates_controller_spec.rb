# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Ml::CandidatesController, feature_category: :mlops do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { project.first_owner }
  let_it_be(:experiment) { create(:ml_experiments, project: project, user: user) }
  let_it_be(:candidate) do
    create(:ml_candidates, experiment: experiment, user: user, project: project).tap do |c|
      c.update!(ci_build: create(:ci_build))
    end
  end

  let(:ff_value) { true }
  let(:candidate_iid) { candidate.iid }
  let(:read_model_experiments) { true }
  let(:write_model_experiments) { true }

  before do
    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?)
                        .with(user, :read_model_experiments, project)
                        .and_return(read_model_experiments)
    allow(Ability).to receive(:allowed?)
                        .with(user, :write_model_experiments, project)
                        .and_return(write_model_experiments)
    sign_in(user)
  end

  shared_examples 'renders 404' do
    it 'renders 404' do
      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  shared_examples '404 if candidate does not exist' do
    context 'when experiment does not exist' do
      let(:candidate_iid) { non_existing_record_id }

      it_behaves_like 'renders 404'
    end
  end

  shared_examples 'requires read_model_experiments' do
    context 'when user does not have access' do
      let(:read_model_experiments) { false }

      it_behaves_like 'renders 404'
    end
  end

  describe 'GET show' do
    before do
      show_candidate
    end

    it 'renders the template' do
      expect(response).to render_template('projects/ml/candidates/show')
    end

    it 'does not perform N+1 sql queries' do
      control_count = ActiveRecord::QueryRecorder.new(skip_cached: false) { show_candidate }

      create_list(:ml_candidate_params, 3, candidate: candidate)
      create_list(:ml_candidate_metrics, 3, candidate: candidate)

      expect { show_candidate }.not_to exceed_all_query_limit(control_count)
    end

    it_behaves_like '404 if candidate does not exist'
    it_behaves_like 'requires read_model_experiments'
  end

  describe 'GET show metrics' do
    let_it_be(:public_project) { create(:project, :public) }
    let_it_be(:public_experiment) { create(:ml_experiments, project: public_project) }

    let_it_be(:long_run) do
      create(:ml_candidates, experiment: public_experiment, project: public_project).tap do |run|
        run.metrics.create!(name: 'num_params', value: 1000, step: 0)
        5.times do |step|
          run.metrics.create!([{ name: 'loss', value: step, step: step }, { name: 'accuracy', value: 1, step: step }])
        end
      end
    end

    let_it_be(:short_run) do
      create(:ml_candidates, experiment: public_experiment, project: public_project).tap do |run|
        run.metrics.create!([{ name: 'loss', value: 1, step: 0 }, { name: 'loss', value: 0.5, step: 1 }])
      end
    end

    before do
      sign_out(user)
      stub_const("#{Ml::CandidateDetailsPresenter}::MAX_EMBEDDED_METRICS", 4)
    end

    def embedded_candidate(run)
      get project_ml_candidate_path(public_project, iid: run.iid)

      expect(response).to have_gitlab_http_status(:ok)

      view_model = Nokogiri::HTML(response.body).at_css('#js-show-ml-candidate')['data-view-model']
      Gitlab::Json::SafeParser.parse(view_model)['candidate']
    end

    it 'embeds only the most recent metric rows of a long run', :aggregate_failures do
      candidate = embedded_candidate(long_run)

      expect(candidate['metrics'].pluck('id')).to eq(long_run.metrics.order(:id).last(4).map(&:id))
      expect(candidate['metrics'].pluck('name')).not_to include('num_params')
      expect(candidate['metricsTruncated']).to be(true)
    end

    it 'embeds every metric row of a short run', :aggregate_failures do
      candidate = embedded_candidate(short_run)

      expect(candidate['metrics'].pluck('id')).to eq(short_run.metrics.order(:id).map(&:id))
      expect(candidate['metricsTruncated']).to be(false)
    end

    context 'when ml_bounded_candidate_metric_reads is disabled' do
      before do
        stub_feature_flags(ml_bounded_candidate_metric_reads: false)
      end

      it 'embeds every metric row of a long run', :aggregate_failures do
        candidate = embedded_candidate(long_run)

        expect(candidate['metrics'].pluck('id')).to match_array(long_run.metrics.map(&:id))
        expect(candidate['metricsTruncated']).to be(false)
      end

      it 'embeds the same metrics of a short run as with the flag enabled' do
        metrics_without_flag = embedded_candidate(short_run)['metrics']

        stub_feature_flags(ml_bounded_candidate_metric_reads: true)

        expect(embedded_candidate(short_run)['metrics']).to match_array(metrics_without_flag)
      end
    end
  end

  describe 'GET promote' do
    before do
      promote_candidate
    end

    it 'renders the template' do
      expect(response).to render_template('projects/ml/candidates/promote')
    end

    it_behaves_like '404 if candidate does not exist'
    describe 'requires write_model_experiments' do
      let(:write_model_experiments) { false }

      it 'is 404' do
        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'DELETE #destroy' do
    let_it_be(:candidate_for_deletion) do
      create(:ml_candidates, project: project, experiment: experiment, user: user)
    end

    let(:candidate_iid) { candidate_for_deletion.iid }

    context 'when experiment can be destroyed' do
      before do
        destroy_candidate
      end

      it 'deletes the experiment', :aggregate_failures do
        expect(response).to have_gitlab_http_status(:found)
        expect(flash[:notice]).to eq('Run removed')
        expect(response).to redirect_to("/#{project.full_path}/-/ml/experiments/#{experiment.iid}")
        expect { Ml::Candidate.find(id: candidate_for_deletion.id) }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it_behaves_like '404 if candidate does not exist'

      describe 'requires write_model_experiments' do
        let(:write_model_experiments) { false }

        it 'is 404' do
          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end

    context 'when candidate can not be destroyed' do
      before do
        allow_next_found_instance_of(Ml::Candidate) do |instance|
          allow(instance).to receive(:destroy).and_return(false)
        end
        destroy_candidate
      end

      it 'returns error status and shows alert' do
        expect(response).to have_gitlab_http_status(:redirect)
        expect(response).to redirect_to project_ml_experiment_path(project, candidate.experiment.iid)
        expect(flash[:alert]).to eq(s_("MlExperimentTracking|Failed to remove run"))
      end
    end
  end

  private

  def show_candidate
    get project_ml_candidate_path(project, iid: candidate_iid)
  end

  def promote_candidate
    get promote_project_ml_candidate_path(project, iid: candidate_iid)
  end

  def destroy_candidate
    delete project_ml_candidate_path(project, candidate_iid)
  end
end
