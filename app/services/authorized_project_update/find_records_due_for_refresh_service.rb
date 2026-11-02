# frozen_string_literal: true

module AuthorizedProjectUpdate
  # Service for finding the authorized_projects records of a user that needs addition or removal.
  #
  # Usage:
  #
  #     user = User.find_by(username: 'alice')
  #     service = AuthorizedProjectUpdate::FindRecordsDueForRefreshService.new(some_user)
  #     service.execute
  class FindRecordsDueForRefreshService
    # A new project's members get access from its own ProjectRecalculateWorker job,
    # which usually runs within a minute or two of creation.
    RECENTLY_CREATED_PROJECT_WINDOW = 10.minutes
    PROJECT_LOOKUP_BATCH_SIZE = 1_000

    def initialize(
      user, source: nil, incorrect_auth_found_callback: nil, missing_auth_found_callback: nil,
      skip_projects_pending_refresh: false, skip_deleted_projects: false)
      @user = user
      @source = source
      @incorrect_auth_found_callback = incorrect_auth_found_callback
      @missing_auth_found_callback = missing_auth_found_callback
      @skip_projects_pending_refresh = skip_projects_pending_refresh
      @skip_deleted_projects = skip_deleted_projects
    end

    def execute
      current = current_authorizations_per_project
      fresh = fresh_access_levels_per_project

      skipped = project_ids_pending_own_refresh(current, fresh) | deleted_project_ids(current, fresh)
      current.except!(*skipped)
      fresh.except!(*skipped)

      # Projects that have more than one authorizations associated with
      # the user needs to be deleted.
      # The correct authorization is added to the ``add`` array in the
      # next stage.
      remove = projects_with_duplicates - skipped
      current.except!(*projects_with_duplicates)

      remove |= current.each_with_object([]) do |(project_id, access_level), array|
        next if fresh[project_id] && fresh[project_id] == access_level

        # rows not in the new list or with a different access level should be
        # removed.

        if incorrect_auth_found_callback
          incorrect_auth_found_callback.call(project_id, access_level)
        end

        array << project_id
      end

      add = fresh.each_with_object([]) do |(project_id, level), array|
        next if current[project_id] && current[project_id] == level

        # rows not in the old list or with a different access level should be
        # added.

        if missing_auth_found_callback
          missing_auth_found_callback.call(project_id, level)
        end

        array << {
          user_id: user.id,
          project_id: project_id,
          access_level: level
        }
      end

      [remove, add]
    end

    def needs_refresh?
      remove, add = execute

      remove.present? || add.present?
    end

    # Both sides of the diff are read as raw [project_id, access_level] pairs
    # rather than ActiveRecord objects. See ProjectAuthorization for why.
    def fresh_access_levels_per_project
      ProjectAuthorization.access_levels_by_project(fresh_authorizations)
    end

    def current_authorizations_per_project
      current_authorizations.to_h
    end

    def current_authorizations
      # Read off the model rather than through `user.project_authorizations`:
      # `pluck` short-circuits to an association's in-memory target when it is
      # already loaded, which would silently return stale rows here.
      @current_authorizations ||= ProjectAuthorization.project_ids_and_access_levels_for(user.id)
    end

    def fresh_authorizations
      Gitlab::ProjectAuthorizations.new(user).calculate
    end

    private

    attr_reader :user, :source, :incorrect_auth_found_callback, :missing_auth_found_callback,
      :skip_projects_pending_refresh, :skip_deleted_projects

    # Safety-net refreshes leave out projects whose own refresh job may not have run yet,
    # so they don't count (or race) access that job is about to write.
    def project_ids_pending_own_refresh(current, fresh)
      return [] unless skip_projects_pending_refresh

      changed = (current.keys | fresh.keys).reject { |id| current[id] == fresh[id] } | projects_with_duplicates

      since = RECENTLY_CREATED_PROJECT_WINDOW.ago

      changed.each_slice(PROJECT_LOOKUP_BATCH_SIZE).flat_map do |ids|
        ProjectAuthorization.project_ids_pending_own_refresh(ids, since: since)
      end
    end

    # Safety-net refreshes also leave out rows whose project has been deleted. Loose-foreign-key
    # cleanup removes those rows, but it can trail a mass deletion by hours, and deleting them
    # here would count that lag as access the primary refresh path had missed.
    def deleted_project_ids(current, fresh)
      return [] unless skip_deleted_projects
      return [] unless Feature.enabled?(:safety_net_skip_deleted_projects, user)

      # The fresh set joins `projects`, so a deleted project can only be on the current side
      candidates = current.keys - fresh.keys

      candidates.each_slice(PROJECT_LOOKUP_BATCH_SIZE).flat_map do |ids|
        ProjectAuthorization.deleted_project_ids(ids)
      end
    end

    def projects_with_duplicates
      @projects_with_duplicates ||= current_authorizations
                                      .group_by(&:first)
                                      .select { |_project_id, authorizations| authorizations.count > 1 }
                                      .keys
    end
  end
end
