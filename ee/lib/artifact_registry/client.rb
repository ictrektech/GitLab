# frozen_string_literal: true

module ArtifactRegistry
  class Client
    include Paths
    include Guards

    PAGINATION_RELS = %i[next prev].freeze

    # Provisioning anchor tuple values. The client owns the wire contract, so
    # callers pass these through rather than defining their own.
    PLATFORM = 'gitlab'
    ENTITY_TYPE_ORGANIZATION = 'organization'
    BILLING_ENTITY_TYPE_TOP_LEVEL_GROUP = 'top_level_group'

    Error = Errors::Error
    AuthorizationError = Errors::AuthorizationError
    UnavailableError = Errors::UnavailableError
    ConfigurationError = Errors::ConfigurationError
    ApiError = Errors::ApiError

    def initialize(current_user: nil, organization: nil, base_url: nil, token_exchange: nil, service_credential: nil)
      @transport = Transport.new(
        base_url: base_url.presence || Configuration.api_url,
        current_user: current_user,
        organization: organization,
        token_exchange: token_exchange || TokenExchange.new,
        service_credential: service_credential || ServiceCredential.new
      )
    end

    def namespace(uuid:)
      guard_segments!(uuid: uuid)

      # The caller looks up a UUID it persisted itself, so a 404 signals drift
      # between Rails and AR: worth logging for operators, but an expected nil
      # outcome for the caller rather than a raised error.
      nil_on_missing(log: true, uuid: uuid) do
        response = service_request(:get, namespace_path(uuid), uuid: uuid)
        attributes = success_body(response, expected: Hash, uuid: uuid)

        # Every reader would return nil, so a body without an id resolves to a
        # namespace that looks present: the opposite of what a drift check needs.
        raise_unexpected_success(response, uuid: uuid) if attributes['id'].blank?

        Namespace.new(attributes)
      end
    end

    def provision_namespace(slug:, platform:, entity_type:, entity_id:, billing_entity_type:, billing_entity_id:)
      guard_present!(slug: slug, platform: platform, entity_type: entity_type, entity_id: entity_id,
        billing_entity_type: billing_entity_type, billing_entity_id: billing_entity_id)
      guard_uuid!(entity_id: entity_id)

      # AR types every anchor field as a JSON string and its strict decoder
      # rejects a number, so billing_entity_id is coerced here: callers hold it
      # as the billing group's integer id.
      body = {
        slug: slug, platform: platform, entity_type: entity_type, entity_id: entity_id,
        billing_entity_type: billing_entity_type, billing_entity_id: billing_entity_id.to_s
      }

      # AR returns 201 on create and 200 on an exact-anchor replay; both carry
      # the namespace. The POST is never retried: a lost response would
      # double-apply provisioning, so recovery belongs to the calling service.
      response = service_request(:post, namespaces_path, body: body)
      attributes = success_body(response, expected: Hash)

      # A hollow namespace would be persisted as a valid mapping by the caller.
      raise_unexpected_success(response) if attributes['id'].blank?

      Namespace.new(attributes)
    end

    def disable_namespace(uuid:)
      namespace_condition(uuid, 'disable')
    end

    def enable_namespace(uuid:)
      namespace_condition(uuid, 'enable')
    end

    def namespace_details(slug:, include_permissions: false)
      guard_segments!(slug: slug)

      # Logged because this route needs no permission and is scoped to the caller's org, so a 404
      # means the slug or org has drifted, not that the caller simply lacks assignments.
      nil_on_missing(log: true, slug: slug) do
        response = user_request(:get, namespace_details_path(slug), slug: slug,
          query: permissions_query(include_permissions))
        attributes = success_body(response, expected: Hash, slug: slug)

        NamespaceDetails.new(attributes,
          verdicts(attributes['permissions'], scope: :namespace, read: :namespace_details, slug: slug,
            requested: include_permissions))
      end
    end

    def repository(slug:, name:, include_permissions: false)
      guard_segments!(slug: slug, name: name)

      nil_on_missing do
        response = user_request(:get, repository_path(slug, name), slug: slug,
          query: permissions_query(include_permissions))
        attributes = success_body(response, expected: Hash, slug: slug)

        repository_with_verdicts(attributes, read: :repository, slug: slug, requested: include_permissions)
      end
    end

    def repositories(
      slug:, format: nil, kind: nil, sort: nil, order: nil, limit: nil, cursor: nil, include_permissions: false)
      guard_segments!(slug: slug)

      query = { format: format, kind: kind, sort: sort, order: order, limit: limit, cursor: cursor }.compact
        .merge(permissions_query(include_permissions))

      # Logged because an unreachable namespace can equally mean the slug this caller holds has
      # drifted from Artifact Registry's.
      nil_on_missing(log: true, slug: slug) do
        response = user_request(:get, repositories_path(slug), slug: slug, query: query)
        attributes_list, permissions = repository_list(response, slug: slug)

        cursors = link_cursors(response, slug: slug)

        Page.new(
          nodes: attributes_list.map do |attributes|
            repository_with_verdicts(attributes, read: :repositories, slug: slug, requested: include_permissions)
          end,
          next_cursor: cursors[:next],
          prev_cursor: cursors[:prev],
          permissions: verdicts(permissions, scope: :namespace, read: :repositories, slug: slug,
            requested: include_permissions)
        )
      end
    end

    def namespace_statistics(slug:)
      guard_segments!(slug: slug)

      path = namespace_statistics_path(slug)

      # path is logged so this read's 404 is distinguishable from the repositories 404 the same
      # drifted slug also triggers; both otherwise log the bare origin alone.
      nil_on_missing(log: true, slug: slug, path: path) do
        response = user_request(:get, path, slug: slug)
        attributes = success_body(response, expected: Hash, slug: slug)

        raise_unexpected_success(response, slug: slug) if missing_expected_keys?(attributes, 'repositories_count',
          'deduplicated_size_bytes')

        NamespaceStatistics.new(attributes)
      end
    end

    def packages(slug:, repository_name:, format:, limit: nil, cursor: nil)
      guard_format!(format, Formats::PACKAGE_FORMATS)

      artifact_page(slug: slug, repository_name: repository_name, format: format, collection: 'packages',
        row_class: Formats.package_class(format), limit: limit, cursor: cursor)
    end

    def images(slug:, repository_name:, format:, limit: nil, cursor: nil)
      guard_format!(format, Formats::IMAGE_FORMATS)

      artifact_page(slug: slug, repository_name: repository_name, format: format, collection: 'images',
        row_class: Image, limit: limit, cursor: cursor)
    end

    def upstream_repositories(slug:, repository_name:, format:, include_permissions: false)
      guard_format!(format, Formats::ARTIFACT_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name)

      path = artifacts_path(slug, repository_name, format, 'upstream_repositories')

      nil_on_missing(log: true, slug: slug) do
        response = user_request(:get, path, slug: slug, query: permissions_query(include_permissions))
        attributes_list = list_rows(response, slug: slug)

        attributes_list.map do |attributes|
          UpstreamRepositoryAssociation.new(attributes,
            upstream_verdicts(attributes, slug: slug, requested: include_permissions))
        end
      end
    end

    def package(slug:, repository_name:, format:, id:)
      guard_format!(format, Formats::PACKAGE_FORMATS)

      artifact(slug: slug, repository_name: repository_name, format: format, collection: 'packages',
        id: id, row_class: Formats.package_class(format))
    end

    def image(slug:, repository_name:, format:, id:)
      guard_format!(format, Formats::IMAGE_FORMATS)

      artifact(slug: slug, repository_name: repository_name, format: format, collection: 'images',
        id: id, row_class: Image)
    end

    def versions(slug:, repository_name:, format:, package_id:, sort: nil, order: nil, limit: nil, cursor: nil)
      guard_format!(format, Formats::PACKAGE_FORMATS)

      # package_id is guarded inside artifact_page (guard_segments!(id:) if sub_collection), the
      # single place every sub-collection read passes through.
      artifact_page(slug: slug, repository_name: repository_name, format: format, collection: 'packages',
        id: package_id, sub_collection: 'versions', row_class: Version,
        extra_query: { sort: sort, order: order }, limit: limit, cursor: cursor,
        log_context: { id: package_id })
    end

    def version(slug:, repository_name:, format:, version_id:)
      guard_format!(format, Formats::PACKAGE_FORMATS)

      # A blank or dot-segment version_id resolves nil here (the single-read guard, so a bad deep
      # link exposes no id-syntax oracle), unlike #version_files, whose sub-collection read raises.
      artifact(slug: slug, repository_name: repository_name, format: format, collection: 'versions',
        id: version_id, row_class: Version)
    end

    def version_statistics(slug:, repository_name:, format:, version_id:)
      guard_format!(format, Formats::PACKAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, version_id: version_id)

      path = sub_collection_path(slug, repository_name, format, 'versions', version_id, 'statistics')

      # 404 and 501 both mean no count available: the route exists before its handler, so an
      # unimplemented endpoint answers 501 rather than a real outage; both map to nil, not an error.
      # Note: 501 still emits one error-tracking event before the raise is swallowed.
      nil_on_missing do
        response = user_request(:get, path, slug: slug)

        VersionStatistics.new(success_body(response, expected: Hash, slug: slug))
      end
    rescue UnavailableError => e
      raise unless e.status == 501

      nil
    end

    # The path carries no format segment; format only picks the family count the 200 body must carry.
    # No 501 rescue, unlike version_statistics: this route shipped with its handler.
    def repository_statistics(slug:, repository_name:, format:)
      guard_format!(format, Formats::ARTIFACT_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name)

      path = repository_statistics_path(slug, repository_name)
      count_key = "#{Formats.collection(format)}_count"

      nil_on_missing do
        response = user_request(:get, path, slug: slug)
        attributes = success_body(response, expected: Hash, slug: slug)

        raise_unexpected_success(response, slug: slug) if missing_expected_keys?(attributes, count_key)

        RepositoryStatistics.new(attributes)
      end
    end

    def version_files(slug:, repository_name:, format:, version_id:, limit: nil, cursor: nil)
      guard_format!(format, Formats::PACKAGE_FORMATS)

      # version_id is guarded inside artifact_page (guard_segments!(id:) if sub_collection), the
      # single place every sub-collection read passes through. The endpoint sorts by file_name
      # alone, so no sort or order argument is forwarded.
      artifact_page(slug: slug, repository_name: repository_name, format: format, collection: 'versions',
        id: version_id, sub_collection: 'files', row_class: Formats.file_class(format),
        limit: limit, cursor: cursor, log_context: { id: version_id })
    end

    def npm_dist_tags(slug:, repository_name:, package_id:, limit: nil, cursor: nil)
      # Endpoint sorts by name only and its default order suits this read, so we forward no sort/order
      # arg even though it accepts one. Dist-tags are npm-only, so the format segment is hard-coded
      # 'npm' rather than a caller arg, which would expose an invalid surface for maven.
      artifact_page(slug: slug, repository_name: repository_name, format: 'npm', collection: 'packages',
        id: package_id, sub_collection: 'tags', row_class: NpmDistTag,
        limit: limit, cursor: cursor, log_context: { id: package_id })
    end

    # rubocop:disable Metrics/ParameterLists -- each keyword maps to a distinct AR contract argument
    def manifests(
      slug:, repository_name:, format:, image_id:,
      include_referrers: false, sort: nil, order: nil, limit: nil, cursor: nil)
      guard_format!(format, Formats::IMAGE_FORMATS)

      # image_id is guarded inside artifact_page (guard_segments!(id:) if sub_collection), the
      # single place every sub-collection read passes through. include_referrers is coerced so a
      # nil renders to false rather than a bare `?include_referrers=` that AR 400s, and a "false"
      # string reads as false rather than flipping referrers on.
      artifact_page(slug: slug, repository_name: repository_name, format: format, collection: 'images',
        id: image_id, sub_collection: 'manifests', row_class: Manifest,
        extra_query: { sort: sort, order: order,
                       include_referrers: Gitlab::Utils.to_boolean(include_referrers, default: false) },
        limit: limit, cursor: cursor, log_context: { id: image_id })
    end
    # rubocop:enable Metrics/ParameterLists

    def manifest(slug:, repository_name:, format:, image_id:, digest:)
      guard_format!(format, Formats::IMAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name)
      return if malformed_deep_link?(image_id, digest)

      path = manifest_path(slug, repository_name, format, image_id, digest)

      # digest and media_type are contract-required, so a body lacking one fails loud here rather
      # than as a GraphQL non-null error on that field.
      read_resource(path, slug: slug, row_class: ManifestDetail, required_keys: %w[id digest media_type])
    end

    def manifest_referrers(slug:, repository_name:, format:, image_id:, digest:, limit: nil, cursor: nil)
      guard_format!(format, Formats::IMAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name)
      return if malformed_deep_link?(image_id, digest)

      # The referrers list hangs off a single manifest, one segment deeper than a manifests list,
      # so it builds on the member path rather than through artifact_page's collection helper.
      # Every row is itself a manifest, so the list element is the same Manifest value object.
      path = "#{manifest_path(slug, repository_name, format, image_id, digest)}/referrers"

      query = { limit: limit, cursor: cursor }.compact

      # Log both the image id and the digest: the route is keyed on the pair, so a 404 is as likely
      # to be the drifted digest as the image id, and a log carrying only one cannot tell them apart.
      nil_on_missing(log: true, slug: slug, id: image_id, digest: digest) do
        response = user_request(:get, path, slug: slug, query: query)
        attributes_list = list_rows(response, slug: slug)

        cursors = link_cursors(response, slug: slug)

        Page.new(
          nodes: attributes_list.map { |attributes| Manifest.new(attributes) },
          next_cursor: cursors[:next],
          prev_cursor: cursors[:prev]
        )
      end
    end

    def create_repository(
      slug:, name:, format:, kind: nil, visibility: nil, description: nil, settings: nil,
      upstream_repository_ids: nil
    )
      guard_segments!(slug: slug, name: name)
      guard_present!(format: format)
      raise ArgumentError, 'settings is only accepted for a remote repository' if settings && kind != 'remote'
      raise ArgumentError, 'settings is required for a remote repository' if kind == 'remote' && settings.nil?

      if upstream_repository_ids && kind != 'virtual'
        raise ArgumentError, 'upstream_repository_ids is only accepted for a virtual repository'
      end

      body = { name: name, format: format, kind: kind, visibility: visibility, description: description,
               settings: settings, upstream_repository_ids: upstream_repository_ids }.compact
      response = user_request(:post, repositories_path(slug), slug: slug, body: body)

      Repository.new(success_body(response, expected: Hash, slug: slug))
    end

    def update_repository(
      slug:, name:, visibility: NOT_PROVIDED, description: NOT_PROVIDED, settings: NOT_PROVIDED,
      upstream_repository_ids: NOT_PROVIDED
    )
      guard_segments!(slug: slug, name: name)
      raise ArgumentError, 'settings must not be nil' if settings.nil?
      raise ArgumentError, 'upstream_repository_ids must not be nil' if upstream_repository_ids.nil?

      body = provided_fields(visibility: visibility, description: description, settings: settings,
        upstream_repository_ids: upstream_repository_ids)
      raise ArgumentError, 'at least one mutable field is required' if body.empty?

      response = user_request(:patch, repository_path(slug, name), slug: slug, body: body)

      Repository.new(success_body(response, expected: Hash, slug: slug))
    end

    def delete_repository(slug:, name:)
      guard_segments!(slug: slug, name: name)

      response = user_request(:delete, repository_path(slug, name), slug: slug, query: { destructive: true })

      raise_unexpected_success(response, slug: slug) unless [202, 204].include?(response.status)

      true
    rescue ApiError => e
      return true if e.status == 404 && e.code == 'not_found'

      log_error(e, method: :delete, code: e.code, slug: slug) if e.status == 400

      raise
    end

    # @return [void]
    def bulk_delete_artifacts(slug:, repository_name:, format:)
      guard_format!(format, Formats::ARTIFACT_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name)

      path = bulk_delete_path(slug, repository_name, format, Formats.collection(format))

      response = user_request(:post, path, slug: slug, body: { delete_all: true })

      # The 202 is the whole outcome: no body, no job handle, so there is nothing to hand back.
      # Another 2xx is contract drift rather than an acceptance, so refuse it instead of reading
      # it as one, which matters most here because this route addresses the whole collection.
      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # @return [void]
    def delete_manifest(slug:, repository_name:, format:, image_id:, digest:)
      guard_format!(format, Formats::IMAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, image_id: image_id, digest: digest)

      path = manifest_path(slug, repository_name, format, image_id, digest)

      response = user_request(:delete, path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # @return [void]
    def delete_container_tag(slug:, repository_name:, format:, image_id:, tag_name:)
      guard_format!(format, Formats::IMAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, image_id: image_id, tag_name: tag_name)

      path = sub_collection_member_path(slug, repository_name, format, 'images', image_id, 'tags', tag_name)

      response = user_request(:delete, path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # @return [void]
    def delete_artifact(slug:, repository_name:, format:, id:)
      guard_format!(format, Formats::ARTIFACT_FORMATS)
      # Guarded here rather than resolved to a not-found the way the reads do: without this an
      # id-less delete would silently build a path with an empty final segment.
      guard_segments!(slug: slug, repository_name: repository_name, id: id)

      path = artifact_path(slug, repository_name, format, Formats.collection(format), id)

      response = user_request(:delete, path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # Inherits Transport::RETRY_OPTIONS' connection-wide :delete exclusion, so the DELETE is not replayed
    # onto the row a first attempt already removed.
    #
    # @return [void]
    def delete_version(slug:, repository_name:, format:, version_id:)
      guard_format!(format, Formats::PACKAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, version_id: version_id)

      path = artifact_path(slug, repository_name, format, 'versions', version_id)

      response = user_request(:delete, path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # @return [void]
    def delete_npm_dist_tag(slug:, repository_name:, tag_id:)
      guard_segments!(slug: slug, repository_name: repository_name, tag_id: tag_id)

      path = artifact_path(slug, repository_name, 'npm', 'tags', tag_id)

      response = user_request(:delete, path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # Sends the subset branch only: the whole-collection delete_all branch has no caller or
    # confirmation design. POST is outside RETRY_OPTIONS[:methods], so no batch is replayed.
    #
    # @param version_ids [Array<String>] the versions to delete, 1 to MAX_BULK_DELETE_BATCH entries
    # @return [void]
    def bulk_delete_versions(slug:, repository_name:, format:, package_id:, version_ids:)
      guard_format!(format, Formats::PACKAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, package_id: package_id)

      guard_batch!(:version_ids, version_ids, MAX_BULK_DELETE_BATCH)

      path = nested_bulk_delete_path(slug, repository_name, format, 'packages', package_id, 'versions')

      response = user_request(:post, path, slug: slug, body: { version_ids: version_ids })

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    # AR skips a listed manifest that an index outside the batch still references, without
    # reporting it, so a 202 does not mean every listed manifest is gone.
    #
    # @param digests [Array<String>] the manifest digests to delete, 1 to MAX_BULK_DELETE_BATCH entries
    # @return [void]
    def bulk_delete_manifests(slug:, repository_name:, format:, image_id:, digests:)
      guard_format!(format, Formats::IMAGE_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, image_id: image_id)

      guard_batch!(:digests, digests, MAX_BULK_DELETE_BATCH)

      path = nested_bulk_delete_path(slug, repository_name, format, 'images', image_id, 'manifests')

      response = user_request(:post, path, slug: slug, body: { digests: digests })

      raise_unexpected_success(response, slug: slug) unless response.status == 202

      nil
    end

    def dissociate_upstream_repository(slug:, repository_name:, format:, association_id:)
      guard_format!(format, Formats::ARTIFACT_FORMATS)
      guard_segments!(slug: slug, repository_name: repository_name, association_id: association_id)

      upstream_repository_path = artifact_path(slug, repository_name, format, 'upstream_repositories', association_id)

      response = user_request(:delete, upstream_repository_path, slug: slug)

      raise_unexpected_success(response, slug: slug) unless response.status == 204

      true
    rescue ApiError => e
      if e.status == 404 && e.code == 'not_found'
        log_error(e, method: :delete, code: e.code, slug: slug, path: upstream_repository_path)
        return true
      end

      raise
    end

    def test_upstream_connection(slug:, name:)
      guard_segments!(slug: slug, name: name)

      response = user_request(:post, repository_test_path(slug, name), slug: slug)
      attributes = success_body(response, expected: Hash, slug: slug)

      raise_unexpected_success(response, slug: slug) if missing_verdict?(attributes)

      ConnectionTestResult.new(attributes)
    end

    def test_namespace_upstream_connection(slug:, format:, url:, credentials: nil)
      guard_format!(format, Formats::ARTIFACT_FORMATS)
      guard_segments!(slug: slug)
      guard_present!(url: url)

      body = { format: format, url: url, credentials: credentials }.compact
      response = user_request(:post, connection_test_path(slug), slug: slug, body: body)
      attributes = success_body(response, expected: Hash, slug: slug)

      raise_unexpected_success(response, slug: slug) if missing_verdict?(attributes)

      NamespaceConnectionTestResult.new(attributes)
    end

    # Batch repository membership check on the service-facing GitLab API
    # surface: does every repository id belong to the namespace? Returns the
    # ids that do not belong ([] means the whole batch does). AR never says why
    # an id failed, so an unknown id and one owned elsewhere are
    # indistinguishable. Any other failure raises, and the caller must fail
    # closed: an outage is not a verdict.
    #
    # @param namespace_id [String] canonical lowercase UUID of the AR namespace
    # @param repository_ids [Array<String>] 1..1000 canonical lowercase UUIDs
    # @return [Array<String>] the submitted ids that failed verification
    def verify_repositories(namespace_id:, repository_ids:)
      guard_verification_input!(namespace_id, repository_ids)

      response = service_request(:post, verifications_path(namespace_id),
        body: { repository_ids: repository_ids }, uuid: namespace_id)

      # The endpoint answers 204 and nothing else when every id belongs, so the
      # status is the whole verdict and there is no body to read. Another 2xx is
      # contract drift rather than an answer, so refuse it instead of reading it
      # as an all-belong verdict.
      raise_unexpected_verification_status(response, namespace_id) unless response.status == 204

      []
    rescue ApiError => e
      raise unless e.status == 422

      verification_failure_ids(e, repository_ids)
    end

    private

    delegate :user_request, :service_request, :log_error, :raise_terminal, to: :@transport, private: true

    # Reports a 404 as an absence rather than raising. Pass log: true where an unresolvable path is
    # not an ordinary outcome for the caller, so the drift behind it stays diagnosable.
    def nil_on_missing(log: false, **log_context)
      yield
    rescue ApiError => e
      raise unless e.status == 404

      log_error(e, **log_context) if log

      nil
    end

    def artifact(slug:, repository_name:, format:, collection:, id:, row_class:)
      guard_segments!(slug: slug, repository_name: repository_name)
      return if malformed_deep_link?(id)

      path = artifact_path(slug, repository_name, format, collection, id)

      read_resource(path, slug: slug, row_class: row_class, required_keys: %w[id])
    end

    # A 404 is the ordinary miss for a user-supplied deep link, so it resolves nil unlogged.
    def read_resource(path, slug:, row_class:, required_keys:)
      nil_on_missing do
        response = user_request(:get, path, slug: slug)
        attributes = success_body(response, expected: Hash, slug: slug)

        raise_unexpected_success(response, slug: slug) if blank_required_keys?(attributes, *required_keys)

        row_class.new(attributes)
      end
    end

    # rubocop:disable Metrics/ParameterLists -- one shared reader for every keyset list; each keyword names a distinct part of the request
    def artifact_page(
      slug:, repository_name:, format:, collection:, row_class:, limit:, cursor:,
      id: nil, sub_collection: nil, extra_query: {}, log_context: {})
      guard_segments!(slug: slug, repository_name: repository_name)
      # A sub-collection read needs its parent id, so guard it here rather than trust each caller:
      # without this an id-less call would silently build a `.../packages//versions` path.
      guard_segments!(id: id) if sub_collection

      query = extra_query.merge(limit: limit, cursor: cursor).compact
      path =
        if sub_collection
          sub_collection_path(slug, repository_name, format, collection, id, sub_collection)
        else
          artifacts_path(slug, repository_name, format, collection)
        end

      nil_on_missing(log: true, slug: slug, **log_context) do
        response = user_request(:get, path, slug: slug, query: query)
        attributes_list = list_rows(response, slug: slug)

        cursors = link_cursors(response, slug: slug)

        Page.new(
          nodes: attributes_list.map { |attributes| row_class.new(attributes) },
          next_cursor: cursors[:next],
          prev_cursor: cursors[:prev]
        )
      end
    end
    # rubocop:enable Metrics/ParameterLists

    # Sends no body, not an empty object: AR's EmptyObject schema 400s any body
    # field, so sending nothing keeps a later argument from silently riding along.
    def namespace_condition(uuid, action)
      guard_segments!(uuid: uuid)

      response = service_request(:post, namespace_condition_path(uuid, action), uuid: uuid)
      attributes = success_body(response, expected: Hash, uuid: uuid)

      # A hollow namespace would read as a successful transition.
      raise_unexpected_success(response, uuid: uuid) if attributes['id'].blank?

      Namespace.new(attributes)
    end

    def success_body(response, expected:, **attribution)
      body = response.body
      return body if body.is_a?(expected)

      raise_unexpected_success(response, **attribution)
    end

    def list_rows(response, slug:)
      attributes_list = success_body(response, expected: Array, slug: slug)
      raise_unexpected_success(response, slug: slug) unless attributes_list.all?(Hash)

      attributes_list
    end

    # `repositories` is always an array, `[]` when empty, so a missing key and a
    # value that is not an array of objects both violate the contract, and
    # list_class is what tells those two apart once body_class reports Hash.
    def repository_list(response, slug:)
      body = success_body(response, expected: Hash, slug: slug)
      list = body['repositories']

      unless list.is_a?(Array) && list.all?(Hash)
        raise_unexpected_success(response, slug: slug, list_class: list.class.name)
      end

      [list, body['permissions']]
    end

    def permissions_query(include_permissions)
      include_permissions ? { include_permissions: true } : {}
    end

    def repository_with_verdicts(attributes, read:, slug:, requested:)
      Repository.new(attributes,
        verdicts(attributes['permissions'], scope: :repository, read: read, slug: slug, requested: requested))
    end

    def upstream_verdicts(attributes, slug:, requested:)
      summary = attributes['upstream_repository']
      permissions = summary['permissions'] if summary.is_a?(Hash)

      verdicts(permissions, scope: :repository, read: :upstream_repositories, slug: slug, requested: requested)
    end

    def verdicts(permissions, scope:, read:, slug:, requested:)
      return unless requested
      return Permissions::Verdicts.absent(scope: scope, read: read, slug: slug) unless permissions.is_a?(Hash)

      Permissions::Verdicts.new(permissions, scope: scope, read: read, slug: slug)
    end

    def missing_verdict?(attributes)
      attributes['passed'].nil?
    end

    # Refuses only a body missing an expected key, not one whose value is null: a present key
    # passes through so the reader, not this guard, decides what a null value means.
    def missing_expected_keys?(attributes, *expected_keys)
      expected_keys.any? { |key| !attributes.key?(key) }
    end

    def blank_required_keys?(attributes, *required_keys)
      required_keys.any? { |key| attributes[key].blank? }
    end

    def raise_unexpected_success(response, **attribution)
      raise_terminal(
        UnavailableError,
        'Artifact Registry returned an unexpected success response',
        response.env&.method,
        status: response.status,
        body_class: response.body.class.name,
        **attribution
      )
    end

    def link_cursors(response, slug:)
      header = response.headers['Link']
      links = Gitlab::Utils::LinkHeaderParser.new(header).parse

      # Reading the header rather than each URI keeps the last page quiet: it still carries rel="prev".
      if header.present? && !links.keys.intersect?(PAGINATION_RELS)
        log_error(Error.new('Artifact Registry Link header yielded no usable rels'), slug: slug)
      end

      PAGINATION_RELS.index_with { |direction| link_cursor(links.dig(direction, :uri), direction, slug: slug) }
    rescue URI::InvalidURIError => e
      log_error(e, slug: slug)
      PAGINATION_RELS.index_with(nil)
    end

    def link_cursor(uri, direction, slug:)
      return unless uri

      cursor = Rack::Utils.parse_query(uri.query)['cursor']
      return cursor if cursor.present?

      log_error(Error.new("Artifact Registry #{direction} link carries no cursor"), slug: slug)
      nil
    end

    # A 422 is the endpoint's "these ids do not belong" verdict, with the
    # failing ids echoed under details['repository_ids'] (allowlisted by
    # ErrorMapping). A 422 whose details carry no failing ids breaks that
    # contract, so it is escalated as an unusable answer rather than a verdict.
    # Held to the ids the caller actually submitted, so a bug on the AR side
    # cannot widen the verdict to a resource this request never named. ADR-009
    # has AR echo the failing ids deduplicated in submitted order, so against a
    # correct response the intersection changes nothing.
    def verification_failure_ids(error, submitted)
      details = error.details.is_a?(Hash) ? error.details['repository_ids'] : nil
      failing_ids = details.is_a?(Array) ? details & submitted : nil

      # An empty intersection is not "every id belongs": a 422 says at least one
      # failed, so a response naming none of the submitted ids is unreadable and
      # must not read as a pass.
      raise_unexpected_verification_failure(error) if failing_ids.blank?

      failing_ids
    end

    def raise_unexpected_verification_status(response, namespace_id)
      raise_terminal(
        UnavailableError,
        'Artifact Registry answered repository verification with an unexpected status',
        :post,
        status: response.status, uuid: namespace_id
      )
    end

    def raise_unexpected_verification_failure(error)
      raise_terminal(
        UnavailableError,
        'Artifact Registry returned an unreadable verification failure',
        :post,
        status: error.status, code: error.code, request_id: error.request_id
      )
    end
  end
end
