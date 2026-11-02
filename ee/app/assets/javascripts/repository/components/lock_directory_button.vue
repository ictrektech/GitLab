<script>
import { GlAlert, GlButton } from '@gitlab/ui';
import { sprintf, __ } from '~/locale';
import { joinPaths, escapeFileUrl } from '~/lib/utils/url_utility';
import { projectTreePath } from '~/lib/utils/path_helpers/repository';
import { createAlert } from '~/alert';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { logError } from '~/lib/logger';
import glLicensedFeaturesMixin from '~/vue_shared/mixins/gl_licensed_features_mixin';
import LockButton from 'ee_component/repository/components/header_area/lock_button.vue';
import currentUserQuery from '~/graphql_shared/queries/current_user.query.graphql';
import projectInfoQuery from 'ee_else_ce/repository/queries/project_info.query.graphql';
import { DEFAULT_BLOB_INFO } from '~/repository/constants';

export default {
  name: 'LockDirectoryButton',
  i18n: {
    fetchError: __('An error occurred while fetching lock information, please try again.'),
    upstreamLockAlert: __(
      'The parent directory "%{path}" is locked. To unlock this directory, unlock "%{path}".',
    ),
    downstreamLockAlert: __(
      'You cannot lock this directory because "%{path}" inside it is locked.',
    ),
    viewLock: __('View lock'),
  },
  components: {
    GlAlert,
    GlButton,
    LockButton,
  },
  mixins: [glLicensedFeaturesMixin()],
  inject: {
    currentRef: {
      default: '',
    },
  },
  props: {
    projectPath: {
      type: String,
      required: true,
    },
    path: {
      type: String,
      required: true,
    },
  },
  apollo: {
    // eslint-disable-next-line @gitlab/vue-no-undef-apollo-properties
    projectInfo: {
      query: projectInfoQuery,
      variables() {
        return {
          projectPath: this.projectPath,
        };
      },
      update({ project } = {}) {
        const allPathLocks = project?.pathLocks?.nodes?.map((lock) => this.mapPathLocks(lock));
        this.pathLock =
          allPathLocks?.find(
            (lock) =>
              this.isDownstreamLock(lock) || this.isUpstreamLock(lock) || this.isExactLock(lock),
          ) || {};
        this.projectUserPermissions = project?.userPermissions || {
          ...DEFAULT_BLOB_INFO.userPermissions,
          createPathLock: false,
        };
        this.rootRef = project?.repository?.rootRef || '';
      },
      error(error) {
        logError(`Unexpected error while fetching projectInfo query`, error);
        this.onFetchError(error);
      },
    },
    // eslint-disable-next-line @gitlab/vue-no-undef-apollo-properties
    currentUser: {
      query: currentUserQuery,
      update({ currentUser } = {}) {
        this.user = { ...currentUser };
      },
      error(error) {
        logError(`Unexpected error while fetching currentUser query`, error);
        this.onFetchError(error);
      },
    },
  },
  data() {
    return {
      pathLock: {},
      rootRef: '',
      user: {},
      projectUserPermissions: {},
    };
  },
  computed: {
    showLockButton() {
      return Boolean(this.glLicensedFeatures.fileLocks && this.user?.id);
    },
    canDestroyDirectoryLock() {
      return Boolean(this.pathLock.isExactLock && this.canDestroyExactLock);
    },
    relatedLockAlert() {
      if (!this.pathLock.isUpstreamLock && !this.pathLock.isDownstreamLock) return null;

      const template = this.pathLock.isUpstreamLock
        ? this.$options.i18n.upstreamLockAlert
        : this.$options.i18n.downstreamLockAlert;
      return sprintf(template, { path: this.pathLock.path }, false);
    },
    lockedPathHref() {
      // The route helper's glob encoding misses `#` and `?`, so escape the lock path ourselves.
      // The parent provides currentRef as null when the page has no explicit ref,
      // which bypasses the inject default, so fall back to the repository root ref.
      return joinPaths(
        projectTreePath(this.projectPath, this.currentRef || this.rootRef),
        escapeFileUrl(this.pathLock.path),
      );
    },
    hasPathLocks() {
      return Object.keys(this.pathLock).length > 0;
    },
    canCreatePathLock() {
      return this.projectUserPermissions.createPathLock;
    },
    canDestroyExactLock() {
      return this.pathLock?.userPermissions.destroyPathLock;
    },
  },
  watch: {
    async path() {
      try {
        await this.$apollo.queries.projectInfo.refetch();
      } catch (error) {
        logError(`Unexpected error while refetch projectInfo query`, error);
        this.onFetchError(error);
      }
    },
  },
  methods: {
    onFetchError(error) {
      Sentry.captureException(error);
      createAlert({ message: this.$options.i18n.fetchError });
    },
    isExactLock(lock) {
      return lock.path === this.path;
    },
    isUpstreamLock(lock) {
      return this.path.startsWith(`${lock.path}/`) && this.path !== lock.path;
    },
    isDownstreamLock(lock) {
      return lock.path.startsWith(this.path) && this.path !== lock.path;
    },
    mapPathLocks(lock) {
      return {
        ...lock,
        isExactLock: this.isExactLock(lock),
        isUpstreamLock: this.isUpstreamLock(lock),
        isDownstreamLock: this.isDownstreamLock(lock),
      };
    },
  },
};
</script>
<template>
  <lock-button
    v-if="showLockButton"
    :is-locked="hasPathLocks"
    :lock-user="pathLock.user || null"
    :locked-at="pathLock.createdAt || null"
    :can-destroy-lock="canDestroyDirectoryLock"
    :can-create-lock="canCreatePathLock"
    :project-path="projectPath"
    :path="path"
    resource-type="directory"
  >
    <template v-if="relatedLockAlert" #disclosure-alert>
      <gl-alert
        variant="warning"
        :dismissible="false"
        class="gl-mx-4 gl-my-3 gl-rounded-base"
        data-testid="related-lock-alert"
      >
        {{ relatedLockAlert }}
      </gl-alert>
    </template>
    <template v-if="relatedLockAlert" #footer>
      <gl-button size="small" :href="lockedPathHref" data-testid="view-locked-path-button">
        {{ $options.i18n.viewLock }}
      </gl-button>
    </template>
  </lock-button>
</template>
