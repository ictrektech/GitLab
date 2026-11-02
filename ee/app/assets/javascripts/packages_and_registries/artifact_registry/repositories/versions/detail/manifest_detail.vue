<script>
import {
  GlAlert,
  GlBadge,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlSkeletonLoader,
  GlTab,
  GlTabs,
  GlToastMixin,
} from '@gitlab/ui';
import { omit } from 'lodash-es';
import { fetchPolicies } from '~/lib/graphql';
import { __, n__, s__, sprintf } from '~/locale';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import DetailLayout from '~/vue_shared/components/detail_layout.vue';
import NotFound from '../../../components/not_found.vue';
import {
  ARTIFACT_VERSIONS_ROUTE_NAME,
  MANIFEST_KIND_INDEX,
  MANIFEST_KIND_LABELS,
  PAGE_NOT_FOUND_TITLE,
  REPOSITORY_FORMAT_LABELS,
  REPOSITORY_FORMAT_LOGO_SIZE_HEADING,
  REPOSITORY_PERMISSION_DELETE_ARTIFACT,
} from '../../../constants';
import deleteManifestMutation from '../../../graphql/mutations/delete_manifest.mutation.graphql';
import getManifestQuery from '../../../graphql/queries/get_manifest.query.graphql';
import getRepositoryPermissionsQuery from '../../../graphql/queries/get_repository_permissions.query.graphql';
import { executeDeleteMutation } from '../../../graphql/utils/delete_mutation';
import { permissionAllows } from '../../../graphql/utils/permissions';
import { manifestDeleteBody, manifestType, shortDigest } from '../../../utils';
import DeleteConfirmationModal from '../../components/delete_confirmation_modal.vue';
import FormatLogo from '../../components/format_logo.vue';
import TagBadges from '../../components/tag_badges.vue';
import ManifestOverview from './manifest_overview.vue';
import ManifestSidebar from './manifest_sidebar.vue';
import ReferrersSection from './referrers_section.vue';

const TAB_QUERY_KEY = 'tab';

const CURSOR_QUERY_KEYS = ['after', 'before'];

const TAB_OVERVIEW = 'overview';

const TAB_REFERRERS = 'referrers';

const TABS = [
  { value: TAB_OVERVIEW, text: __('Overview') },
  { value: TAB_REFERRERS, text: s__('ArtifactRegistry|Referrers') },
];

export default {
  name: 'ArtifactRegistryManifestDetail',
  components: {
    ClipboardButton,
    DeleteConfirmationModal,
    DetailLayout,
    FormatLogo,
    GlAlert,
    GlBadge,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlSkeletonLoader,
    GlTab,
    GlTabs,
    ManifestOverview,
    ManifestSidebar,
    NotFound,
    ReferrersSection,
    TagBadges,
  },
  mixins: [GlToastMixin],
  inject: ['breadCrumbState', 'organizationGid'],
  data() {
    return {
      repository: undefined,
      userPermissions: null,
      hasError: false,
      referrersStatus: null,
      manifestToDelete: null,
      isDeleting: false,
    };
  },
  apollo: {
    repository: {
      query: getManifestQuery,
      variables() {
        return {
          organizationId: this.organizationGid,
          name: this.repositoryName,
          artifactId: this.artifactId,
          digest: this.digest,
        };
      },
      update: ({ organization }) => organization?.artifactRegistryRepository ?? null,
      // Not redundant with `error` below: this query sets no `errorPolicy`, so vue-apollo calls
      // `result` on failure too. Clearing unconditionally here would drop the alert.
      result({ error }) {
        this.hasError = Boolean(error);
      },
      error() {
        this.hasError = true;
      },
    },
    userPermissions: {
      query: getRepositoryPermissionsQuery,
      fetchPolicy: fetchPolicies.CACHE_AND_NETWORK,
      variables() {
        return { organizationId: this.organizationGid, name: this.repositoryName };
      },
      update: ({ organization }) =>
        organization?.artifactRegistryRepository?.userPermissions ?? null,
      result({ error }) {
        if (error) this.userPermissions = null;
      },
      error() {
        this.userPermissions = null;
      },
    },
  },
  computed: {
    repositoryName() {
      return this.$route.params.id;
    },
    artifactId() {
      return this.$route.params.artifactId;
    },
    digest() {
      return this.$route.params.digest;
    },
    manifestKey() {
      return [this.repositoryName, this.artifactId, this.digest].join('/');
    },
    isLoading() {
      return this.$apollo.queries.repository.loading;
    },
    format() {
      return this.repository?.format;
    },
    formatLabel() {
      return REPOSITORY_FORMAT_LABELS[this.format];
    },
    manifest() {
      return this.repository?.manifest ?? null;
    },
    image() {
      return this.repository?.image ?? null;
    },
    imageName() {
      return this.image?.name ?? '';
    },
    shortenedDigest() {
      return shortDigest(this.manifest?.digest);
    },
    type() {
      return manifestType(this.manifest ?? {});
    },
    isIndex() {
      return this.type.kind === MANIFEST_KIND_INDEX;
    },
    isReferrer() {
      return Boolean(this.type.subjectDigest);
    },
    kindLabel() {
      if (!this.isIndex) return MANIFEST_KIND_LABELS[this.type.kind];

      const platforms = this.manifest?.childrenCount ?? 0;

      return n__(
        'ArtifactRegistry|Index · %d platform',
        'ArtifactRegistry|Index · %d platforms',
        platforms,
      );
    },
    mediaTypeLabel() {
      return sprintf(this.$options.i18n.mediaType, { mediaType: this.manifest?.mediaType });
    },
    artifactTypeLabel() {
      return sprintf(this.$options.i18n.artifactType, {
        artifactType: this.manifest?.artifactType,
      });
    },
    subjectDigestLabel() {
      return sprintf(this.$options.i18n.subjectDigest, {
        digest: this.manifest?.subjectDigest,
      });
    },
    digestLabel() {
      let message = this.$options.i18n.imageDigest;

      if (this.isIndex) message = this.$options.i18n.indexDigest;
      if (this.isReferrer) message = this.$options.i18n.manifestDigest;

      return sprintf(message, { digest: this.manifest?.digest });
    },
    tags() {
      return this.manifest?.tags ?? [];
    },
    toggleText() {
      return sprintf(this.$options.i18n.moreActions, { name: this.shortenedDigest });
    },
    canDelete() {
      if (this.$apollo.queries.userPermissions.loading) return false;

      return permissionAllows(this.userPermissions, REPOSITORY_PERMISSION_DELETE_ARTIFACT);
    },
    deleteItem() {
      return {
        text: this.$options.i18n.deleteManifestLabel,
        variant: 'danger',
        action: () => {
          this.manifestToDelete = this.manifest;
        },
      };
    },
    deleteModalCopy() {
      const { deleteTitle, deleteManifestLabel } = this.$options.i18n;

      return {
        title: deleteTitle,
        body: manifestDeleteBody(this.type.kind),
        name: this.shortenedDigest,
        actionText: deleteManifestLabel,
      };
    },
    isNotFound() {
      return !this.isLoading && !this.hasError && !this.manifest;
    },
    isPopulated() {
      return Boolean(this.manifest);
    },
    // The heading and description slots render outside the layout's content, so they carry their
    // own gate: a failed refetch would otherwise leave the header standing over the alert.
    rendersManifest() {
      return this.isPopulated && !this.isLoading && !this.hasError;
    },
    // Settling is read off the data, not `isLoading`: Vue evaluates a watcher's getter before
    // vue-apollo registers the query, so publishing early blanks the name the list resolved.
    resolvedBreadCrumbNames() {
      if (this.repository === undefined && !this.hasError) return null;

      return { artifact: this.imageName, manifest: shortDigest(this.digest) };
    },
    referrersCount() {
      return this.manifest?.referrersCount ?? null;
    },
    visibleTabs() {
      if (this.referrersCount !== 0) return TABS;

      return TABS.filter(({ value }) => value !== TAB_REFERRERS);
    },
    tabs() {
      return this.visibleTabs.map((tab) => {
        const count = tab.value === TAB_REFERRERS ? this.referrersCount : null;

        return {
          ...tab,
          count,
          isOverview: tab.value === TAB_OVERVIEW,
          isReferrers: tab.value === TAB_REFERRERS,
          countSrText:
            count === null
              ? null
              : n__('ArtifactRegistry|%d referrer', 'ArtifactRegistry|%d referrers', count),
        };
      });
    },
    activeTab() {
      const requested = this.$route.query[TAB_QUERY_KEY];

      return this.tabs.some(({ value }) => value === requested) ? requested : TAB_OVERVIEW;
    },
    activeTabLabel() {
      return this.tabs.find(({ value }) => value === this.activeTab)?.text ?? '';
    },
    tabIndex: {
      get() {
        return Math.max(
          this.tabs.findIndex(({ value }) => value === this.activeTab),
          0,
        );
      },
      set(index) {
        const tab = this.tabs[index]?.value;

        if (!tab || tab === this.activeTab) return;

        this.$router.push({
          path: this.$route.path,
          query: { ...omit(this.$route.query, CURSOR_QUERY_KEYS), [TAB_QUERY_KEY]: tab },
        });
      },
    },
    statusMessage() {
      // GlAlert renders role="alert" for the danger variant and announces the failure itself,
      // so naming it here would put the same text through a second live region.
      if (this.hasError) return '';
      if (this.isLoading) return this.$options.i18n.loading;
      if (this.isNotFound) return this.$options.i18n.notFound;

      // Only once the section has reported: until then the tab name is the honest answer,
      // and a zero count would otherwise announce an empty list the page has not read yet.
      if (this.activeTab === TAB_REFERRERS && this.referrersStatus) {
        if (this.referrersStatus.hasError) return '';
        if (this.referrersStatus.isLoading) return this.$options.i18n.referrersLoading;
        if (!this.referrersStatus.count) return this.$options.i18n.noReferrers;
      }

      if (!this.imageName) {
        return sprintf(this.$options.i18n.loadedWithoutImage, {
          tab: this.activeTabLabel,
          digest: this.shortenedDigest,
        });
      }

      return sprintf(this.$options.i18n.loaded, {
        tab: this.activeTabLabel,
        digest: this.shortenedDigest,
        name: this.imageName,
      });
    },
  },
  watch: {
    manifestKey() {
      this.manifestToDelete = null;
    },
    resolvedBreadCrumbNames(names) {
      if (!names) return;

      this.breadCrumbState.updateArtifactName(names.artifact);
      this.breadCrumbState.updateManifestName(names.manifest);
    },
  },
  methods: {
    async deleteManifest({ digest }) {
      if (this.isDeleting) return;

      this.isDeleting = true;
      const { repositoryName, artifactId } = this;

      try {
        const accepted = await executeDeleteMutation(this.$apollo, {
          mutation: deleteManifestMutation,
          input: { name: repositoryName, imageId: artifactId, digest },
        });

        if (!accepted) return;

        this.$toast.show(this.$options.i18n.deletionScheduled);
        this.$router.push({
          name: ARTIFACT_VERSIONS_ROUTE_NAME,
          params: { id: repositoryName, artifactId },
        });
      } finally {
        this.isDeleting = false;
      }
    },
  },
  i18n: {
    unavailable: s__('ArtifactRegistry|The Artifact Registry service is unavailable.'),
    loading: s__('ArtifactRegistry|Loading manifest details.'),
    referrersLoading: s__('ArtifactRegistry|Loading referrers.'),
    noReferrers: s__('ArtifactRegistry|Nothing refers to this manifest.'),
    loaded: s__('ArtifactRegistry|%{tab} tab for manifest %{digest} of %{name}.'),
    loadedWithoutImage: s__('ArtifactRegistry|%{tab} tab for manifest %{digest}.'),
    notFound: PAGE_NOT_FOUND_TITLE,
    mediaType: s__('ArtifactRegistry|Media type: %{mediaType}'),
    artifactType: s__('ArtifactRegistry|Artifact type: %{artifactType}'),
    subjectDigest: s__('ArtifactRegistry|Subject digest: %{digest}'),
    indexDigest: s__('ArtifactRegistry|Index digest: %{digest}'),
    imageDigest: s__('ArtifactRegistry|Image digest: %{digest}'),
    manifestDigest: s__('ArtifactRegistry|Manifest digest: %{digest}'),
    copyDigest: s__('ArtifactRegistry|Copy digest'),
    moreActions: s__('ArtifactRegistry|More actions for %{name}'),
    deleteManifestLabel: s__('ArtifactRegistry|Delete manifest'),
    deleteTitle: s__('ArtifactRegistry|Delete manifest?'),
    deletionScheduled: s__('ArtifactRegistry|Manifest successfully scheduled for deletion.'),
  },
  logoSize: REPOSITORY_FORMAT_LOGO_SIZE_HEADING,
};
</script>

<template>
  <div>
    <span
      class="gl-sr-only"
      aria-live="polite"
      aria-atomic="true"
      data-testid="manifest-announcement"
      >{{ statusMessage }}</span
    >

    <detail-layout :loading="isLoading">
      <template #loading>
        <gl-skeleton-loader :lines="2" :width="500" />
      </template>

      <!-- The wrapper renders unconditionally: Vue 2 reads a slot whose only output is a `v-if`
           comment as empty and falls back to the layout's own empty h1. -->
      <template #heading-wrapper>
        <div class="gl-flex gl-min-w-0 gl-grow gl-flex-wrap gl-items-center gl-gap-3">
          <template v-if="rendersManifest">
            <format-logo :format="format" :size="$options.logoSize" />
            <span class="gl-sr-only" data-testid="manifest-format-name">{{ formatLabel }}</span>

            <h1 class="gl-heading-1 !gl-m-0" data-testid="page-heading">
              <span class="gl-wrap-anywhere" data-testid="manifest-digest">{{
                shortenedDigest
              }}</span>
            </h1>

            <tag-badges :tags="tags" />

            <gl-badge data-testid="manifest-kind">{{ kindLabel }}</gl-badge>
          </template>
        </div>
      </template>

      <template v-if="rendersManifest && canDelete" #actions>
        <gl-disclosure-dropdown
          icon="ellipsis_v"
          :toggle-text="toggleText"
          :loading="isDeleting"
          text-sr-only
          category="tertiary"
          no-caret
          placement="bottom-end"
          data-testid="manifest-actions"
        >
          <gl-disclosure-dropdown-item :item="deleteItem" data-testid="delete-manifest" />
        </gl-disclosure-dropdown>
      </template>

      <template v-if="rendersManifest" #description>
        <span v-if="imageName" class="gl-block gl-wrap-anywhere" data-testid="image-name">{{
          imageName
        }}</span>

        <span class="gl-block gl-text-sm gl-wrap-anywhere" data-testid="manifest-media-type">{{
          mediaTypeLabel
        }}</span>

        <span
          v-if="manifest.artifactType"
          class="gl-block gl-text-sm gl-wrap-anywhere"
          data-testid="manifest-artifact-type"
          >{{ artifactTypeLabel }}</span
        >

        <span
          v-if="isReferrer"
          class="gl-block gl-text-sm gl-wrap-anywhere"
          data-testid="manifest-subject-digest"
          >{{ subjectDigestLabel }}</span
        >

        <span class="gl-flex gl-items-center gl-gap-2">
          <span class="gl-text-sm gl-wrap-anywhere" data-testid="manifest-full-digest">{{
            digestLabel
          }}</span>
          <clipboard-button
            :text="manifest.digest"
            :title="$options.i18n.copyDigest"
            category="tertiary"
            size="small"
          />
        </span>
      </template>

      <gl-alert v-if="hasError" variant="danger" :dismissible="false">
        {{ $options.i18n.unavailable }}
      </gl-alert>

      <not-found v-else-if="isNotFound" />

      <gl-tabs v-else-if="rendersManifest" v-model="tabIndex" lazy content-class="gl-py-5">
        <gl-tab
          v-for="tab in tabs"
          :key="tab.value"
          :title="tab.text"
          :tab-count="tab.count"
          :tab-count-sr-text="tab.countSrText"
        >
          <manifest-overview
            v-if="tab.isOverview"
            :format="format"
            :name="repositoryName"
            :image-name="imageName"
            :manifest="manifest"
          />

          <referrers-section
            v-else-if="tab.isReferrers"
            :name="repositoryName"
            :artifact-id="artifactId"
            :digest="manifest.digest"
            @status-changed="referrersStatus = $event"
          />
        </gl-tab>
      </gl-tabs>

      <template v-if="rendersManifest" #sidebar>
        <manifest-sidebar :repository="repository" :manifest="manifest" :artifact-id="artifactId" />
      </template>
    </detail-layout>

    <delete-confirmation-modal
      v-model="manifestToDelete"
      v-bind="deleteModalCopy"
      @confirm="deleteManifest"
    />
  </div>
</template>
