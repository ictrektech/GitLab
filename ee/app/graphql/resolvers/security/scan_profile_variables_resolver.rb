# frozen_string_literal: true

module Resolvers
  module Security
    class ScanProfileVariablesResolver < BaseResolver
      type [Types::Security::ScanProfiles::VariableType], null: false
      description 'Configuration variables a scan profile of the given type can set.'

      argument :scan_type, Types::Security::ScanProfileTypeEnum,
        required: true,
        description: 'Scan profile type to return the configuration variables for.'

      def resolve(scan_type:)
        mappings = ::Security::ScanProfiles::Configuration::CiVariables::MAPPINGS.fetch(scan_type.to_sym, {})

        mappings.map do |key, mapping|
          { key: key.to_s.camelize(:lower), env_var: mapping[:env] }
        end
      end
    end
  end
end
