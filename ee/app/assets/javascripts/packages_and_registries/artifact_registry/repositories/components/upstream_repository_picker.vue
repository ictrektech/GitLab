<script>
import {
  GlAlert,
  GlButton,
  GlIntersectionObserver,
  GlLoadingIcon,
  GlTokenSelector,
} from '@gitlab/ui';
import { fetchPolicies } from '~/lib/graphql';
import { n__, s__, sprintf } from '~/locale';
import {
  GRAPHQL_PAGE_SIZE,
  REPOSITORY_FORMAT_LABELS,
  REPOSITORY_KIND_HOSTED,
  REPOSITORY_KIND_LABELS,
  REPOSITORY_KIND_REMOTE,
  UPSTREAM_REPOSITORIES_CAP,
} from '../../constants';
import getUpstreamRepositoryCandidatesQuery from '../../graphql/queries/get_upstream_repository_candidates.query.graphql';

const ATTACHABLE_KINDS = [REPOSITORY_KIND_HOSTED, REPOSITORY_KIND_REMOTE];

export default {
  name: 'ArtifactRegistryUpstreamRepositoryPicker',
  i18n: {
    search: s__('ArtifactRegistry|Search by name or URL'),
    capReached: s__('ArtifactRegistry|Maximum number of upstream repositories reached.'),
  },
  components: {
    GlAlert,
    GlButton,
    GlIntersectionObserver,
    GlLoadingIcon,
    GlTokenSelector,
  },
  inject: ['organizationGid'],
  props: {
    format: {
      type: String,
      required: true,
    },
    excludedIds: {
      type: Array,
      required: true,
    },
    listSize: {
      type: Number,
      required: true,
    },
  },
  emits: ['add', 'close'],
  data() {
    return {
      candidates: undefined,
      loaded: [],
      search: '',
      announcement: '',
      hasError: false,
    };
  },
  apollo: {
    candidates: {
      query: getUpstreamRepositoryCandidatesQuery,
      fetchPolicy: fetchPolicies.NETWORK_ONLY,
      nextFetchPolicy: fetchPolicies.CACHE_FIRST,
      variables() {
        return {
          organizationId: this.organizationGid,
          kinds: ATTACHABLE_KINDS,
          formats: [this.format],
          first: GRAPHQL_PAGE_SIZE,
        };
      },
      update: ({ organization }) =>
        organization?.artifactRegistryRepositories ?? { nodes: [], pageInfo: {} },
      result({ loading }) {
        if (loading) return;

        this.appendPage();
      },
      error() {
        this.hasError = true;
      },
    },
  },
  computed: {
    loading() {
      return this.$apollo.queries.candidates.loading;
    },
    pageInfo() {
      return this.candidates?.pageInfo ?? {};
    },
    hasNextPage() {
      return Boolean(this.pageInfo.hasNextPage);
    },
    attachable() {
      return this.loaded.filter(({ id }) => !this.excludedIds.includes(id));
    },
    isCapReached() {
      return this.listSize >= UPSTREAM_REPOSITORIES_CAP;
    },
    visible() {
      if (this.isCapReached) return [];

      const term = this.search.trim().toLowerCase();

      if (!term) return this.attachable;

      return this.attachable.filter(
        (candidate) =>
          candidate.name.toLowerCase().includes(term) ||
          (this.candidateUrl(candidate) ?? '').toLowerCase().includes(term),
      );
    },
    hasNoAttachable() {
      return this.attachable.length === 0 && !this.hasNextPage && !this.loading;
    },
    hasNoMatch() {
      return Boolean(this.search.trim()) && this.visible.length === 0 && this.attachable.length > 0;
    },
    noAttachableText() {
      return sprintf(
        s__(
          'ArtifactRegistry|No %{format} repositories are available to add. Create a hosted or remote repository first.',
        ),
        { format: REPOSITORY_FORMAT_LABELS[this.format] },
      );
    },
    noMatchText() {
      return this.hasNextPage
        ? s__(
            'ArtifactRegistry|0 loaded repositories match. Keep scrolling to load and search more.',
          )
        : s__('ArtifactRegistry|No repositories match your search.');
    },
  },
  watch: {
    search(value) {
      if (!value) return;

      this.announcement = n__(
        'ArtifactRegistry|%d repository matches.',
        'ArtifactRegistry|%d repositories match.',
        this.visible.length,
      );
    },
  },
  mounted() {
    this.$refs.tokenSelector.focusTextInput();
  },
  // Picks never stay as chips; each one moves straight into the list.
  noTokens: [],
  methods: {
    appendPage() {
      const nodes = this.candidates?.nodes ?? [];
      const before = this.attachable.length;
      const known = new Set(this.loaded.map(({ id }) => id));

      this.loaded = [...this.loaded, ...nodes.filter(({ id }) => !known.has(id))];

      if (this.attachable.length > before) {
        this.announcement = n__(
          'ArtifactRegistry|%d repository loaded.',
          'ArtifactRegistry|%d repositories loaded.',
          this.attachable.length,
        );
      }
    },
    loadNextPage() {
      this.$apollo.queries.candidates
        .fetchMore({
          variables: { after: this.pageInfo.endCursor },
          updateQuery: (_, { fetchMoreResult }) => fetchMoreResult,
        })
        .then(() => {
          this.hasError = false;
        })
        .catch(() => {
          this.hasError = true;
        });
    },
    candidateUrl({ settings }) {
      return settings?.url ?? null;
    },
    kindLabel(kind) {
      return REPOSITORY_KIND_LABELS[kind] || kind;
    },
    // Add each pick at once: a separate Add button sat under the open menu,
    // so unconfirmed picks were silently dropped on submit.
    addPicked({ id, name, kind, sizeBytes, settings }) {
      if (this.isCapReached) return;

      this.$emit('add', [
        { id, name, kind, sizeBytes: sizeBytes ?? null, url: settings?.url ?? null },
      ]);
      // GlTokenSelector closes its menu on every pick. A click reopens it on refocus,
      // but an Enter pick leaves focus in place, so reopen it for the next pick.
      this.$nextTick(() => this.$refs.tokenSelector?.openDropdown());
    },
  },
};
</script>

<template>
  <div class="gl-p-3" data-testid="upstream-repository-picker">
    <gl-alert v-if="hasError" class="gl-mb-3" variant="danger" :dismissible="false">
      {{ s__('ArtifactRegistry|Failed to load repositories.') }}
    </gl-alert>

    <gl-token-selector
      ref="tokenSelector"
      :selected-tokens="$options.noTokens"
      :dropdown-items="visible"
      :hide-dropdown-with-no-items="false"
      menu-class="!gl-w-full"
      :placeholder="$options.i18n.search"
      :aria-label="$options.i18n.search"
      data-testid="upstream-repository-picker-search"
      @token-add="addPicked"
      @keydown.enter.prevent
      @text-input="search = $event"
    >
      <template #dropdown-item-content="{ dropdownItem }">
        <div class="gl-flex gl-items-center gl-gap-3 gl-py-3">
          <div class="gl-grow">
            <span class="gl-wrap-anywhere" data-testid="candidate-name">{{
              dropdownItem.name
            }}</span>
            <span
              v-if="candidateUrl(dropdownItem)"
              class="gl-block gl-text-sm gl-text-subtle gl-wrap-anywhere"
              data-testid="candidate-url"
              >{{ candidateUrl(dropdownItem) }}</span
            >
          </div>
          <span class="gl-text-sm gl-text-subtle" data-testid="candidate-kind">{{
            kindLabel(dropdownItem.kind)
          }}</span>
        </div>
      </template>

      <template #no-results-content>
        <span v-if="isCapReached" data-testid="picker-cap-reached">{{
          $options.i18n.capReached
        }}</span>
        <span v-else-if="hasNoAttachable" data-testid="picker-no-attachable">{{
          noAttachableText
        }}</span>
        <span v-else-if="hasNoMatch" data-testid="picker-no-match">{{ noMatchText }}</span>
      </template>

      <template #dropdown-footer>
        <gl-intersection-observer
          v-if="hasNextPage"
          data-testid="picker-sentinel"
          @appear="loadNextPage"
        />
        <gl-loading-icon v-if="loading" size="sm" />
      </template>
    </gl-token-selector>

    <div class="gl-mt-3 gl-flex gl-gap-3">
      <gl-button size="small" data-testid="picker-done" @click="$emit('close')">
        {{ __('Done') }}
      </gl-button>
    </div>

    <span
      class="gl-sr-only"
      aria-live="polite"
      aria-atomic="true"
      data-testid="upstream-repository-picker-announcement"
      >{{ announcement }}</span
    >
  </div>
</template>
