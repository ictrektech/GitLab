# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Packages::MlModel::PackageForCandidateService, feature_category: :mlops do
  let_it_be(:project, freeze: false) { create(:project) }
  let_it_be(:user, freeze: false) { project.creator }
  let_it_be(:model, freeze: false) { create(:ml_models, user: project.owner, project: project) }
  let_it_be(:model_version, freeze: false) { create(:ml_model_versions, :with_package, model: model, version: '0.1.0') }
  let_it_be(:model_version_candidate, freeze: false) { model_version.candidate }
  let_it_be(:model_candidate, freeze: false) do
    create(:ml_candidates, user: project.owner, project: project, experiment: model.default_experiment)
  end

  let_it_be(:model_candidate_with_package, freeze: false) do
    create(:ml_candidates, experiment: model.default_experiment, user: project.owner, project: project).tap do |c|
      c.package = create(:ml_model_package, project: project, name: c.package_name, version: c.package_version)
    end
  end

  let_it_be(:not_model_candidate, freeze: false) { create(:ml_candidates, user: project.owner, project: project) }

  let(:base_params) do
    {
      candidate: candidate
    }
  end

  let(:params) { base_params }

  describe '#execute' do
    subject(:execute_service) { described_class.new(project, user, params).execute }

    context 'when candidate does not have a package' do
      let(:candidate) { model_candidate }

      it 'creates a package' do
        expect { execute_service }.to change { Packages::Package.count }.by(1)

        package = execute_service

        expect(candidate.reload.package).to eq(package)
        expect(package.name).to eq(model.name)
        expect(package.version).to eq("candidate_#{candidate.iid}")
        expect(package.project).to eq(project)
      end
    end

    context 'when candidate already has a package' do
      let(:candidate) { model_candidate_with_package }

      it 'returns the package' do
        expect { execute_service }.not_to change { Packages::Package.count }

        package = execute_service

        expect(package).to eq(candidate.package)
      end
    end

    context 'when candidate is nil' do
      let(:candidate) { nil }

      it { is_expected.to be_nil }
    end

    context 'when candidate belongs to a model version' do
      let(:candidate) { model_version_candidate }

      it 'creates a package' do
        expect { execute_service }.to change { candidate.package }.from(nil)
      end
    end

    context 'when candidate does not belong to a model' do
      let(:candidate) { not_model_candidate }

      it 'creates a package' do
        expect { execute_service }.to change { candidate.package }.from(nil)
      end
    end

    context 'when a concurrent upload creates the package after the lookup' do
      let(:candidate) do
        create(:ml_candidates, user: project.owner, project: project, experiment: model.default_experiment)
      end

      let!(:concurrent_package) do
        build(:ml_model_package, project: project, name: candidate.package_name, version: candidate.package_version)
      end

      let(:service) { described_class.new(project, user, params) }
      let(:not_unique_error) { ActiveRecord::RecordNotUnique.new('duplicate key value violates unique constraint') }
      let(:other_invalid_error) { ActiveRecord::RecordInvalid.new(Packages::MlModel::Package.new.tap(&:validate)) }

      subject(:execute_service) { service.execute }

      context 'when the uniqueness validation finds the concurrent package' do
        it 'retries the lookup and returns the concurrent package', :aggregate_failures do
          expect_next_instance_of(Packages::MlModel::Package) { concurrent_package.save! }

          expect(execute_service).to eq(concurrent_package)
          expect(candidate.reload.package).to eq(concurrent_package)
        end
      end

      context 'when the unique index rejects the insert' do
        it 'retries the lookup and returns the concurrent package', :aggregate_failures do
          expect_next_instance_of(Packages::MlModel::Package) do |package|
            concurrent_package.save!
            # The validation ran before the concurrent upload committed.
            allow(package).to receive(:valid?).and_return(true)
          end

          expect(execute_service).to eq(concurrent_package)
          expect(candidate.reload.package).to eq(concurrent_package)
        end
      end

      context 'when the retry fails too' do
        it 'raises the error' do
          expect(service).to receive(:find_or_create_package!).twice.and_raise(not_unique_error)

          expect { execute_service }.to raise_error(ActiveRecord::RecordNotUnique)
        end
      end

      context 'when the package is invalid for another reason' do
        it 'raises the error without a retry' do
          expect(service).to receive(:find_or_create_package!).once.and_raise(other_invalid_error)

          expect { execute_service }.to raise_error(ActiveRecord::RecordInvalid)
        end
      end
    end
  end
end
