# frozen_string_literal: true

require 'spec_helper'
require 'digest'

RSpec.describe Ci::Slsa::PublishProvenanceService, feature_category: :artifact_security do
  let(:service) { described_class.new(build) }

  include_context 'with build, pipeline and artifacts'

  describe '#execute' do
    subject(:result) { service.execute }

    context "when passing invalid parameters" do
      context "when the build is nil" do
        let(:service) { described_class.new(nil) }

        it "returns an error" do
          expect(result[:message]).to eq("Unable to find build")
          expect(result[:status]).to eq(:error)
        end
      end

      context "when exceptions are raised" do
        let(:container_publisher) { instance_double(SupplyChain::ContainerProvenancePublisher) }

        before do
          allow(SupplyChain::ContainerProvenancePublisher).to receive(:should_publish?).with(build)
            .and_return(true)
          allow(SupplyChain::ArtifactProvenancePublisher).to receive(:should_publish?)
            .and_return(false)

          allow(SupplyChain::ContainerProvenancePublisher)
            .to receive(:new).once
            .with(build)
            .and_return(container_publisher)

          allow(container_publisher).to receive(:publish).and_raise(exception)
        end

        context "when a catchable exception is raised" do
          let(:exception) { SupplyChain::ProvenancePublisher::Error }

          it "logs and catches the exception" do
            expect(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception).once
            expect(result[:status]).to eq(:error)
          end
        end

        context "when another kind of exception is raised" do
          let(:exception) { StandardError }

          it "raises the exception without being rescued" do
            expect(Gitlab::ErrorTracking).not_to receive(:track_and_raise_for_dev_exception)
            expect { result }.to raise_error(exception)
          end
        end
      end
    end

    context "when checking the project visibility" do
      let(:artifact_publisher) { instance_double(SupplyChain::ArtifactProvenancePublisher) }
      let(:attestations) { [instance_double(SupplyChain::Attestation)] }

      shared_examples "publishes attestations" do
        it "publishes artifact attestations", :aggregate_failures do
          allow(SupplyChain::ContainerProvenancePublisher).to receive(:should_publish?).with(build).and_return(false)
          allow(SupplyChain::ArtifactProvenancePublisher).to receive(:should_publish?).with(build).and_return(true)
          expect(SupplyChain::ArtifactProvenancePublisher).to receive(:new).with(build).and_return(artifact_publisher)
          expect(artifact_publisher).to receive(:publish).and_return([attestations, true])

          expect(result[:status]).to eq(:success)
          expect(result[:message]).to eq("Attestations persisted")
        end
      end

      shared_examples "only publishes with LOCAL_CA" do
        context "with ATTEST_METHOD set to SIGSTORE" do
          let(:attest_method) { "SIGSTORE" }

          it "returns an error without calling the publishers", :aggregate_failures do
            expect(SupplyChain::ArtifactProvenancePublisher).not_to receive(:new)
            expect(SupplyChain::ContainerProvenancePublisher).not_to receive(:new)

            expect(result[:status]).to eq(:error)
            expect(result[:message]).to eq("SIGSTORE attestations are only enabled for public projects")
          end
        end

        context "with ATTEST_METHOD set to LOCAL_CA" do
          let(:attest_method) { "LOCAL_CA" }

          it_behaves_like "publishes attestations"
        end

        context "without ATTEST_METHOD" do
          it_behaves_like "publishes attestations"
        end
      end

      context "when the project is public" do
        context "with ATTEST_METHOD set to SIGSTORE" do
          let(:attest_method) { "SIGSTORE" }

          it_behaves_like "publishes attestations"
        end
      end

      context "when the project is private" do
        let_it_be(:project) { create(:project, :private, group: group) }
        let(:build) { create(:ci_build, project: project) }

        it_behaves_like "only publishes with LOCAL_CA"
      end

      context "when the project is internal" do
        let_it_be(:project) { create(:project, :internal, group: group) }
        let(:build) { create(:ci_build, project: project) }

        it_behaves_like "only publishes with LOCAL_CA"
      end
    end

    context "when calling publishers and they return success" do
      let(:artifact_publisher) { instance_double(SupplyChain::ArtifactProvenancePublisher) }
      let(:attestations) { [instance_double(SupplyChain::Attestation)] }
      let(:container_publisher) { instance_double(SupplyChain::ContainerProvenancePublisher) }

      let(:empty_success) { [[], true] }
      let(:empty_error) { [[], false] }
      let(:error) { [attestations, false] }
      let(:success) { [attestations, true] }

      let!(:empty_message) { "No attestations performed" }
      let!(:error_message) { "Error occurred when publishing attestations" }
      let!(:success_message) { "Attestations persisted" }

      before do
        allow(SupplyChain::ArtifactProvenancePublisher)
          .to receive(:new).once
          .with(build)
          .and_return(artifact_publisher)

        allow(SupplyChain::ContainerProvenancePublisher)
          .to receive(:new).once
          .with(build)
          .and_return(container_publisher)

        allow(SupplyChain::ArtifactProvenancePublisher).to receive(:should_publish?)
          .and_return(should_publish_artifacts)

        allow(SupplyChain::ContainerProvenancePublisher).to receive(:should_publish?)
          .and_return(should_publish_containers)
      end

      where(:should_publish_containers, :should_publish_artifacts, :containers_response, :artifacts_response,
        :expected_status, :expected_message) do
        [
          [true, true, ref(:success), ref(:success), :success, ref(:success_message)],
          [true, false, ref(:success), nil, :success, ref(:success_message)],
          [false, true, nil, ref(:success), :success, ref(:success_message)],

          [true, true, ref(:error), ref(:success), :error, ref(:error_message)],
          [true, true, ref(:success), ref(:error), :error, ref(:error_message)],
          [false, true, nil, ref(:error), :error, ref(:error_message)],
          [true, false, ref(:error), nil, :error, ref(:error_message)],
          [true, true, ref(:empty_error), ref(:empty_error), :error, ref(:error_message)],

          [true, true, ref(:empty_success), ref(:empty_success), :success, ref(:empty_message)],
          [false, false, nil, nil, :success, ref(:empty_message)]
        ]
      end

      with_them do
        it "behaves correctly" do
          expect(SupplyChain::ContainerProvenancePublisher).to receive(:should_publish?).with(build)
            .and_return(should_publish_containers)

          expect(SupplyChain::ArtifactProvenancePublisher).to receive(:should_publish?).with(build)
            .and_return(should_publish_artifacts)

          if should_publish_artifacts
            expect(artifact_publisher).to receive(:publish).and_return(artifacts_response)
          else
            expect(artifact_publisher).not_to receive(:publish)
          end

          if should_publish_containers
            expect(container_publisher).to receive(:publish).and_return(containers_response)
          else
            expect(container_publisher).not_to receive(:publish)
          end

          expect(result[:status]).to eq(expected_status)
          expect(result[:message]).to eq(expected_message)
        end
      end
    end
  end
end
