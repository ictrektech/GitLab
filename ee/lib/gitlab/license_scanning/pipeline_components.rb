# frozen_string_literal: true

module Gitlab
  module LicenseScanning
    class PipelineComponents
      def initialize(pipeline:, user: ::Gitlab::LicenseScanning::UNSCOPED)
        @pipeline = pipeline
        @user = user
      end

      def fetch
        sbom_reports.reports.flat_map do |sbom_report|
          sbom_report.components.map do |component|
            next unless component.purl
            next unless supported_for_license_scanning?(component.purl.type)

            Hashie::Mash.new(name: component.name,
              purl_type: component.purl.type,
              version: component.version,
              path: sbom_report.source&.input_file_path,
              licenses: component.licenses)
          end.reject(&:blank?)
        end
      end

      private

      attr_reader :pipeline, :user

      # Scope sbom artifact reads to what `user` may access. `UNSCOPED` (internal/system
      # callers) reads every report; any other value - a real user, or nil for a guest -
      # is filtered to the artifacts that viewer may read.
      def sbom_reports
        return pipeline.sbom_reports if user == ::Gitlab::LicenseScanning::UNSCOPED

        pipeline.accessible_sbom_reports(user)
      end

      def supported_for_license_scanning?(purl_type)
        ::Enums::Sbom.dependency_scanning_purl_type?(purl_type)
      end
    end
  end
end
