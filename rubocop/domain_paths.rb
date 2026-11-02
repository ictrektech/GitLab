# frozen_string_literal: true

module RuboCop
  # Files in domains/<name>/ mirror the top-level app/, lib/, spec/ and ee/ trees.
  # Match cop Include and Exclude globs against the top-level equivalent too, so a
  # cop scoped to `app/workers/**/*` also applies to `domains/<name>/app/workers/`.
  # Literal file paths, as used by .rubocop_todo/, still need the real domain path.
  module DomainPaths
    DOMAIN_PREFIX = %r{\Adomains/[^/]+/}

    private

    def file_name_matches_any?(file, parameter, default_result)
      return true if super
      return false unless file.include?('domains/')

      relative_path = config.path_relative_to_config(file)
      return false unless relative_path.match?(DOMAIN_PREFIX)

      globs = Array(cop_config[parameter]).select { |pattern| pattern.is_a?(Regexp) || pattern.include?('*') }
      return false if globs.empty?

      host_path = relative_path.sub(DOMAIN_PREFIX, '')
      patterns = FilePatterns.from(globs)
      patterns.match?(host_path) || patterns.match?(File.join(config.base_dir_for_path_parameters, host_path))
    end
  end
end

RuboCop::Cop::Base.prepend(RuboCop::DomainPaths)
