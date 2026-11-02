<script>
import {
  GlBadge,
  GlButton,
  GlDisclosureDropdown,
  GlDisclosureDropdownItem,
  GlLoadingIcon,
  GlPopover,
  GlSprintf,
  GlTable,
  GlToastMixin,
  GlTruncate,
} from '@gitlab/ui';
import { isEqual, uniqueId } from 'lodash-es';
import {
  MANIFEST_DETAIL_ROUTE_NAME,
  MANIFEST_KIND_IMAGE,
  MANIFEST_KIND_INDEX,
  MANIFEST_KIND_LABELS,
  MANIFEST_KIND_SBOM,
  MANIFEST_KIND_SIGNATURE,
  MANIFEST_KIND_SLSA,
  MANIFESTS_TABLE_FIELDS,
  REPOSITORY_PERMISSION_DELETE_ARTIFACT,
} from 'ee/packages_and_registries/artifact_registry/constants';
import deleteManifestMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/delete_manifest.mutation.graphql';
import getArtifactManifestsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_artifact_manifests.query.graphql';
import { executeDeleteMutation } from 'ee/packages_and_registries/artifact_registry/graphql/utils/delete_mutation';
import { permissionAllows } from 'ee/packages_and_registries/artifact_registry/graphql/utils/permissions';
import {
  humanSize,
  manifestDeleteBody,
  manifestType,
  platformLabel,
  shortDigest,
} from 'ee/packages_and_registries/artifact_registry/utils';
import { createAlert } from '~/alert';
import { copyToClipboard } from '~/lib/utils/copy_to_clipboard';
import { __, n__, s__, sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import DeleteConfirmationModal from '../components/delete_confirmation_modal.vue';
import PullCommandDrawer from './pull_command_drawer.vue';

const REFERRER_MESSAGES = {
  [MANIFEST_KIND_SIGNATURE]: s__('ArtifactRegistry|Signature for %{digest}'),
  [MANIFEST_KIND_SBOM]: s__('ArtifactRegistry|SBOM attestation for %{digest}'),
  [MANIFEST_KIND_SLSA]: s__('ArtifactRegistry|SLSA attestation for %{digest}'),
};

const platformsOf = (manifest, kind) => {
  if (kind === MANIFEST_KIND_INDEX && manifest.childrenCount > 0) {
    return {
      text: n__(
        'ArtifactRegistry|%d platform',
        'ArtifactRegistry|%d platforms',
        manifest.childrenCount,
      ),
      badge: true,
    };
  }

  return { text: kind === MANIFEST_KIND_IMAGE ? platformLabel(manifest) : '', badge: false };
};

const referrersOf = ({ referrersCount }) =>
  referrersCount > 0
    ? n__('ArtifactRegistry|%d referrer', 'ArtifactRegistry|%d referrers', referrersCount)
    : '';

const tagsOf = ({ tagsPreview, tagsCount }) => {
  if (!Array.isArray(tagsPreview)) return { preview: null, more: '' };

  const extra = Math.max((tagsCount ?? 0) - tagsPreview.length, 0);

  return {
    preview: tagsPreview,
    more: extra ? sprintf(s__('ArtifactRegistry|+%{count} more'), { count: extra }) : '',
  };
};

export default {
  name: 'ArtifactRegistryManifestsTable',
  components: {
    DeleteConfirmationModal,
    GlBadge,
    GlButton,
    GlDisclosureDropdown,
    GlDisclosureDropdownItem,
    GlLoadingIcon,
    GlPopover,
    GlSprintf,
    GlTable,
    GlTruncate,
    PullCommandDrawer,
    TimeAgoTooltip,
  },
  mixins: [GlToastMixin],
  props: {
    manifests: {
      type: Array,
      required: true,
    },
    format: {
      type: String,
      required: true,
    },
    artifact: {
      type: Object,
      required: true,
    },
    name: {
      type: String,
      required: true,
    },
    imageId: {
      type: String,
      required: true,
    },
    hiddenColumns: {
      type: Array,
      required: false,
      default: () => [],
    },
    sort: {
      type: Object,
      required: true,
    },
    isLoading: {
      type: Boolean,
      required: false,
      default: false,
    },
    permissions: {
      type: Object,
      required: false,
      default: null,
    },
  },
  emits: ['sort-changed'],
  data() {
    return {
      manifestToDelete: null,
      pendingDeletionDigests: [],
      activeManifest: null,
      // Remounts the table: `GlTable` seeds its sort state in `data()` and never watches it.
      externalSortCount: 0,
      requestedSort: null,
      referencedByPrefix: uniqueId('manifest-referenced-by-'),
    };
  },
  computed: {
    canDelete() {
      return permissionAllows(this.permissions, REPOSITORY_PERMISSION_DELETE_ARTIFACT);
    },
    fields() {
      return MANIFESTS_TABLE_FIELDS.filter(({ key }) => !this.hiddenColumns.includes(key));
    },
    rows() {
      return this.manifests.map((manifest) => {
        const type = manifestType(manifest);
        const shortened = shortDigest(manifest.digest);

        return {
          ...manifest,
          type,
          shortened,
          linkLabel: this.manifestLinkLabel(shortened),
          route: this.manifestRoute(manifest.digest),
          tags: tagsOf(manifest),
          platforms: platformsOf(manifest, type.kind),
          referrers: referrersOf(manifest),
          referencedBy: this.referencedByOf(manifest),
        };
      });
    },
    activeManifestTags() {
      return this.activeManifest?.tags ?? [];
    },
    deleteModalCopy() {
      const { deleteTitle, deleteManifestLabel } = this.$options.i18n;

      return {
        title: deleteTitle,
        body: manifestDeleteBody(this.manifestToDelete?.type?.kind),
        name: shortDigest(this.manifestToDelete?.digest),
        actionText: deleteManifestLabel,
      };
    },
  },
  watch: {
    sort(sort) {
      if (isEqual(sort, this.requestedSort)) return;

      this.externalSortCount += 1;
    },
  },
  methods: {
    requestSort({ sortBy, sortDesc }) {
      this.requestedSort = { sortBy, sortDesc };

      this.$emit('sort-changed', { sortBy, sortDesc });
    },
    humanSize,
    manifestRoute(digest) {
      return {
        name: MANIFEST_DETAIL_ROUTE_NAME,
        params: { id: this.name, artifactId: this.imageId, digest },
      };
    },
    manifestLinkLabel(digest) {
      return sprintf(this.$options.i18n.manifest, { digest });
    },
    referencedByOf({ id, parentsPreview }) {
      if (!Array.isArray(parentsPreview) || !parentsPreview.length) return null;

      const links = parentsPreview.map((digest) => ({
        digest,
        shortened: shortDigest(digest),
        route: this.manifestRoute(digest),
      }));

      return {
        targetId: `${this.referencedByPrefix}${id}`,
        links,
        label: sprintf(
          n__(
            'ArtifactRegistry|Referenced by manifest %{digests}',
            'ArtifactRegistry|Referenced by manifests %{digests}',
            links.length,
          ),
          { digests: links.map(({ shortened }) => shortened).join(', ') },
        ),
      };
    },
    standaloneLabel({ kind }) {
      return MANIFEST_KIND_LABELS[kind];
    },
    referrerMessage({ kind, artifactType }) {
      if (REFERRER_MESSAGES[kind]) return REFERRER_MESSAGES[kind];

      return artifactType ? this.$options.i18n.rawReferrer : this.$options.i18n.referrer;
    },
    toggleText(digest) {
      return sprintf(s__('ArtifactRegistry|More actions for %{name}'), {
        name: shortDigest(digest),
      });
    },
    deleteItem(manifest) {
      return {
        text: this.$options.i18n.deleteManifestLabel,
        variant: 'danger',
        action: () => {
          this.manifestToDelete = manifest;
        },
      };
    },
    pullCommandItem({ digest, tagsPreview }) {
      return {
        text: s__('ArtifactRegistry|View pull command'),
        action: () => {
          this.activeManifest = { digest, tags: tagsPreview ?? [] };
        },
      };
    },
    copyDigestItem(digest) {
      return {
        text: s__('ArtifactRegistry|Copy digest'),
        action: () => this.copyDigest(digest),
      };
    },
    async copyDigest(digest) {
      try {
        await copyToClipboard(digest);
        this.$toast.show(s__('ArtifactRegistry|Digest copied to clipboard.'));
      } catch (error) {
        Sentry.captureException(error);
      }
    },
    isPendingDeletion({ digest }) {
      return this.pendingDeletionDigests.includes(digest);
    },
    async deleteManifest({ digest }) {
      if (this.pendingDeletionDigests.includes(digest)) return;

      this.pendingDeletionDigests.push(digest);

      try {
        const accepted = await executeDeleteMutation(this.$apollo, {
          mutation: deleteManifestMutation,
          input: { name: this.name, imageId: this.imageId, digest },
        });

        if (!accepted) return;

        try {
          await this.$apollo.getClient().refetchQueries({ include: [getArtifactManifestsQuery] });
        } catch (error) {
          createAlert({
            message: __('Something went wrong. Please try again.'),
            error,
            captureError: true,
          });
          return;
        }

        this.$toast.show(this.$options.i18n.deletionScheduled);
      } finally {
        this.pendingDeletionDigests = this.pendingDeletionDigests.filter(
          (pendingDigest) => pendingDigest !== digest,
        );
      }
    },
  },
  i18n: {
    manifest: s__('ArtifactRegistry|Manifest %{digest}'),
    rawReferrer: s__('ArtifactRegistry|%{artifactType} for %{digest}'),
    referrer: s__('ArtifactRegistry|Referrer for %{digest}'),
    deleteManifestLabel: s__('ArtifactRegistry|Delete manifest'),
    deleteTitle: s__('ArtifactRegistry|Delete manifest?'),
    deletionScheduled: s__('ArtifactRegistry|Manifest successfully scheduled for deletion.'),
  },
};
</script>

<template>
  <div>
    <gl-table
      :key="externalSortCount"
      :busy="isLoading"
      :fields="fields"
      :items="rows"
      :sort-by="sort.sortBy"
      :sort-desc="sort.sortDesc"
      no-local-sorting
      stacked="md"
      @sort-changed="requestSort"
    >
      <template #table-busy>
        <!-- The guard keeps the spinner tied to the busy state: a stubbed table renders
             this slot whatever `busy` holds. -->
        <gl-loading-icon v-if="isLoading" size="sm" class="gl-my-5" />
      </template>

      <template #cell(digest)="{ item }">
        <span class="gl-flex gl-items-center gl-justify-end gl-gap-2 @md/panel:gl-justify-start">
          <span data-testid="manifest-digest">
            <router-link
              :to="item.route"
              :aria-label="item.linkLabel"
              class="gl-font-semibold gl-text-default gl-wrap-anywhere"
              >{{ item.shortened }}</router-link
            >
          </span>
          <template v-if="item.referencedBy">
            <gl-button
              :id="item.referencedBy.targetId"
              :aria-label="item.referencedBy.label"
              icon="link"
              category="tertiary"
              size="small"
              data-testid="manifest-referenced-by"
            />
            <gl-popover :target="item.referencedBy.targetId" placement="top">
              <gl-sprintf :message="s__('ArtifactRegistry|referenced by %{manifests}')">
                <template #manifests>
                  <span v-for="(link, index) in item.referencedBy.links" :key="link.digest">
                    <template v-if="index > 0">, </template>
                    <router-link :to="link.route" data-testid="manifest-referenced-by-link">{{
                      link.shortened
                    }}</router-link>
                  </span>
                </template>
              </gl-sprintf>
            </gl-popover>
          </template>
        </span>
      </template>

      <template #cell(tags)="{ value }">
        <div v-if="value.preview?.length" class="gl-flex gl-flex-wrap gl-items-center gl-gap-2">
          <gl-badge
            v-for="tag in value.preview"
            :key="tag"
            variant="info"
            data-testid="manifest-tag"
            >{{ tag }}</gl-badge
          >
          <span
            v-if="value.more"
            class="gl-text-sm gl-text-subtle"
            data-testid="manifest-more-tags"
            >{{ value.more }}</span
          >
        </div>
        <span v-else-if="value.preview" class="gl-text-subtle" data-testid="manifest-untagged">{{
          s__('ArtifactRegistry|untagged')
        }}</span>
        <span v-else class="gl-text-subtle" aria-hidden="true" data-testid="manifest-untagged"
          >&mdash;</span
        >
      </template>

      <template #cell(type)="{ item, value }">
        <span data-testid="manifest-type">
          <template v-if="value.subjectDigest">
            <gl-sprintf :message="referrerMessage(value)">
              <template v-if="value.artifactType" #artifactType>
                <gl-truncate
                  :text="value.artifactType"
                  class="gl-min-w-0 gl-max-w-26"
                  position="middle"
                  with-tooltip
                />
              </template>
              <template #digest>
                <router-link
                  :to="manifestRoute(item.subjectDigest)"
                  :aria-label="manifestLinkLabel(value.subjectDigest)"
                  data-testid="manifest-subject-link"
                  >{{ value.subjectDigest }}</router-link
                >
              </template>
            </gl-sprintf>
          </template>
          <template v-else>{{ standaloneLabel(value) }}</template>
        </span>
      </template>

      <template #cell(platforms)="{ value }">
        <gl-badge v-if="value.badge" data-testid="manifest-platforms">{{ value.text }}</gl-badge>
        <span v-else-if="value.text" data-testid="manifest-platforms">{{ value.text }}</span>
        <span v-else class="gl-text-subtle" aria-hidden="true" data-testid="manifest-platforms"
          >&mdash;</span
        >
      </template>

      <template #cell(referrers)="{ value }">
        <gl-badge v-if="value" data-testid="manifest-referrers">{{ value }}</gl-badge>
        <span v-else class="gl-text-subtle" aria-hidden="true" data-testid="manifest-referrers"
          >&mdash;</span
        >
      </template>

      <template #cell(size)="{ item }">
        <span data-testid="manifest-size">{{ humanSize(item.size) }}</span>
      </template>

      <template #cell(createdAt)="{ item }">
        <time-ago-tooltip :time="item.createdAt" data-testid="manifest-published" />
      </template>

      <template #cell(actions)="{ item }">
        <gl-disclosure-dropdown
          icon="ellipsis_v"
          :toggle-text="toggleText(item.digest)"
          :loading="isPendingDeletion(item)"
          text-sr-only
          category="tertiary"
          no-caret
          placement="bottom-end"
          data-testid="manifest-actions"
        >
          <gl-disclosure-dropdown-item
            :item="pullCommandItem(item)"
            data-testid="view-pull-command"
          />
          <gl-disclosure-dropdown-item
            :item="copyDigestItem(item.digest)"
            data-testid="copy-digest"
          />
          <gl-disclosure-dropdown-item
            v-if="canDelete"
            :item="deleteItem(item)"
            data-testid="delete-manifest"
          />
        </gl-disclosure-dropdown>
      </template>
    </gl-table>

    <pull-command-drawer
      :open="Boolean(activeManifest)"
      :format="format"
      :artifact="artifact"
      :name="name"
      :digest="activeManifest?.digest ?? ''"
      :tags="activeManifestTags"
      @close="activeManifest = null"
    />

    <delete-confirmation-modal
      v-model="manifestToDelete"
      v-bind="deleteModalCopy"
      @confirm="deleteManifest"
    />
  </div>
</template>
