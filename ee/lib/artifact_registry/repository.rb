# frozen_string_literal: true

module ArtifactRegistry
  class Repository < ValueObject
    include TimeCoercion

    attr_reader :permissions

    expose_attribute :id, :name, :format, :kind, :visibility, :description,
      :artifacts_count, :downloads_count, :size_bytes, :created_by, :updated_by

    def initialize(attributes = {}, permissions = nil)
      super(attributes)
      @permissions = permissions
    end

    def packages?
      Formats::PACKAGE_FORMATS.include?(format)
    end

    def images?
      Formats::IMAGE_FORMATS.include?(format)
    end

    def npm?
      format == 'npm'
    end

    def hosted?
      kind == 'hosted'
    end

    def remote?
      kind == 'remote'
    end

    def virtual?
      kind == 'virtual'
    end

    def created_at
      parse_time(@attributes['created_at'])
    end

    def last_updated_at
      parse_time(@attributes['last_updated_at'])
    end

    def settings
      settings = @attributes['settings']

      settings.is_a?(Hash) ? settings : {}
    end
  end
end
