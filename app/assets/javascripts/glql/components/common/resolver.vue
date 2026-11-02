<script>
import { GlKeysetPagination } from '@gitlab/ui';
import { pick } from 'lodash-es';
import { s__, sprintf } from '~/locale';
import { sha256 } from '~/lib/utils/text_utility';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { InternalEvents } from '~/tracking';
import {
  AGGREGATED_AUTO_PAGE_SIZE,
  ANALYTICS_PAGINATION_BY_DISPLAY_TYPE,
  DEFAULT_PAGE_SIZE,
  DEFAULT_DISPLAY_TYPE,
  EXECUTION_QUEUE_DEFAULT,
  LIMIT_PAGED_DISPLAY_TYPES,
  MAX_AUTO_PAGINATED_ROWS,
  MODE_ANALYTICS,
  PAGINATION_AUTO,
  PAGINATION_BY_DISPLAY_TYPE,
  PAGINATION_LOAD_MORE,
  PAGINATION_PAGED,
} from '~/glql/constants';
import { parse } from '../../core/parser';
import { execute } from '../../core/executor';
import { transform } from '../../core/transformer';
import DataPresenter from '../presenters/data.vue';
import {
  appendPage,
  currentPage,
  emptyPageList,
  goToPage,
  hasCachedNextPage,
  hasPreviousPage,
  markCurrentPageAsLast,
  startPageList,
} from '../../utils/page_list';
import GlqlPagination from './pagination.vue';

// No display type maps to this: it is what `pagination` falls back to when neither
// strategy applies, for an aggregated display outside analytics mode, or one outside
// LIMIT_PAGED_DISPLAY_TYPES with a `limit:`.
const PAGINATION_NONE = 'none';

export default {
  name: 'GlqlResolver',
  PAGINATION_LOAD_MORE,
  PAGINATION_PAGED,
  components: {
    DataPresenter,
    GlKeysetPagination,
    GlqlPagination,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    glqlQuery: {
      required: true,
      type: String,
    },
    trackingEventName: {
      required: false,
      type: String,
      default: '',
    },
    /**
     * Namespace to compile the query against, as `{ group }` or `{ project }`.
     * When null, the namespace is derived from the current URL.
     */
    scope: {
      required: false,
      type: Object,
      default: null,
    },
    /**
     * Comparison settings: `query` is a second query run alongside `glqlQuery`, with its
     * result exposed as `comparisonData`, and `metric` names the metric used for comparison.
     * `bindings` stands in for the main query's bindings when the comparison covers another
     * period. Only dashboard panels set this.
     */
    comparison: {
      required: false,
      type: Object,
      default: null,
    },
    /**
     * Request queue the queries run on. Resolvers on a page that name the same queue share
     * its concurrency limit, so dashboard panels use their own to load side by side.
     */
    queue: {
      required: false,
      type: String,
      default: EXECUTION_QUEUE_DEFAULT,
    },
    /**
     * Order among requests waiting on the queue: lower runs first, equal keeps arrival order.
     * Dashboard panels pass their grid position so a view fills top to bottom.
     */
    priority: {
      required: false,
      type: Number,
      default: 0,
    },
    /**
     * Control bindings, each names a query field and the value to inject into it.
     * The compiler rewrites the query's filters from these, so the caller never templates the
     * query text. Only dashboard panels set this.
     */
    bindings: {
      required: false,
      type: Array,
      default: () => [],
    },
  },
  emits: ['change'],
  data() {
    return {
      loading: false,

      data: undefined,
      comparisonData: undefined,
      comparisonPending: false,
      query: undefined,
      config: undefined,
      variables: undefined,
      fields: undefined,
      mode: undefined,
      source: undefined,
      error: undefined,
      resultsTruncated: false,

      // `paged` only: every page fetched so far, so Previous never refetches.
      pageList: emptyPageList(),
      pageLoading: false,

      // The pagination loop is a plain async function, so destroying the component does not
      // stop it. Parents remount this component instead of mutating its props.
      discarded: false,
    };
  },
  computed: {
    hasDisplayType() {
      return Boolean(this.config?.display);
    },
    // The backend's cap, so each auto-paginated page is as large as it allows.
    aggregatedPageSize() {
      return gon.aggregation_max_page_size ?? AGGREGATED_AUTO_PAGE_SIZE;
    },
    /**
     * Page size for an analytics-mode display in LIMIT_PAGED_DISPLAY_TYPES with a positive whole
     * `limit:`. Every row is fetched and the presenter pages over them, so the limit never reaches
     * the server. Null otherwise, and `limit` is the fetch page size, which the server rejects if
     * invalid. Outside analytics mode nothing walks the pages, so `limit` stays a fetch size.
     */
    displayPageSize() {
      const limit = Number(this.config?.limit);

      if (this.mode !== MODE_ANALYTICS || !LIMIT_PAGED_DISPLAY_TYPES.has(this.config?.display)) {
        return null;
      }
      return Number.isInteger(limit) && limit > 0 ? limit : null;
    },
    pagination() {
      const display = this.config?.display ?? DEFAULT_DISPLAY_TYPE;
      const strategy =
        (this.mode === MODE_ANALYTICS && ANALYTICS_PAGINATION_BY_DISPLAY_TYPE[display]) ||
        PAGINATION_BY_DISPLAY_TYPE[display];

      if (strategy === PAGINATION_LOAD_MORE || strategy === PAGINATION_PAGED) return strategy;
      if (
        strategy === PAGINATION_AUTO &&
        this.mode === MODE_ANALYTICS &&
        (this.config?.limit == null || this.displayPageSize)
      ) {
        return PAGINATION_AUTO;
      }

      return PAGINATION_NONE;
    },
    hasNextPage() {
      if (this.pagination === PAGINATION_PAGED) return Boolean(this.data?.pageInfo?.hasNextPage);

      return (
        this.pagination === PAGINATION_LOAD_MORE &&
        Boolean(this.data?.count && this.data.nodes?.length < this.data.count)
      );
    },
    isPaged() {
      return this.pagination === PAGINATION_PAGED;
    },
    hasPreviousPage() {
      return hasPreviousPage(this.pageList);
    },
    // The query returns the total row count, so the page count is known before the last page.
    pageCounter() {
      const total = Number(this.data?.count);
      if (!this.isPaged || !(total > 0)) return null;

      const pageSize = this.config?.limit ?? DEFAULT_PAGE_SIZE;
      return sprintf(s__('Glql|Page %{current} of %{total}'), {
        current: this.pageList.index + 1,
        total: Math.ceil(total / pageSize),
      });
    },
  },
  created() {
    // Not reactive: aborting it drops this instance's requests still waiting in the queue.
    this.abortController = new AbortController();
  },
  mounted() {
    this.executeQuery();
  },
  beforeDestroy() {
    this.discarded = true;
    this.abortController.abort();
  },
  methods: {
    resetData() {
      this.data = undefined;
      this.comparisonData = undefined;
      this.comparisonPending = false;
      this.query = undefined;
      this.config = undefined;
      this.variables = undefined;
      this.fields = undefined;
      this.mode = undefined;
      this.source = undefined;
      this.error = undefined;
      this.resultsTruncated = false;
      this.pageList = emptyPageList();
      this.pageLoading = false;
    },

    emitChange() {
      this.$emit(
        'change',
        pick(this, [
          'query',
          'data',
          'comparisonData',
          'config',
          'variables',
          'fields',
          'mode',
          'source',
          'error',
          'loading',
          'hasNextPage',
          'pagination',
          'resultsTruncated',
        ]),
      );
    },

    setVariable(key, value) {
      if (this.variables?.[key]) {
        this.variables[key].value = value;
      }
    },

    async executeQuery() {
      if (!this.glqlQuery.trim()) return;

      this.resetData();

      this.loading = true;
      this.emitChange();

      try {
        const { query, config, variables, fields, mode, source } = await parse(
          this.glqlQuery,
          this.scope,
          { bindings: this.bindings },
        );

        this.query = query;
        this.config = config;
        this.variables = variables;
        this.fields = fields;
        this.mode = mode;
        this.source = source;

        // Honor an explicit `limit:`, unless it sizes a chart's display-side pages. Otherwise,
        // lists and tables get the default page size; aggregated displays take a full page
        // that `autoPaginate` walks to the end of.
        if (this.config.limit != null && !this.displayPageSize) {
          this.setVariable('limit', this.config.limit);
        } else if ([PAGINATION_LOAD_MORE, PAGINATION_PAGED].includes(this.pagination)) {
          this.setVariable('limit', DEFAULT_PAGE_SIZE);
        } else if (this.pagination === PAGINATION_AUTO) {
          this.setVariable('limit', this.aggregatedPageSize);
        }

        // Started before the comparison, so the main query is queued first, and awaited only once
        // the comparison is underway, so both run at once. Every request carries the source as
        // its tag, so a panel reload can drop all of them from the dashboard result cache.
        const mainRequest = execute(query, variables, {
          queue: this.queue,
          priority: this.priority,
          signal: this.abortController.signal,
          tag: this.glqlQuery,
        });
        const comparisonRequest = this.fetchComparison();
        this.comparisonPending = Boolean(this.comparison?.query);
        const executionResult = await mainRequest;

        this.data = await transform(executionResult, { fields, mode, source });
        // A result wider than one page drops its comparison, so release the reserved column now
        // rather than when loading clears.
        if (this.data?.count > this.aggregatedPageSize) this.comparisonPending = false;

        if (this.pagination === PAGINATION_PAGED) {
          this.pageList = startPageList({ nodes: this.data.nodes, pageInfo: this.data.pageInfo });
        }
        if (this.pagination === PAGINATION_AUTO) await this.autoPaginate();

        const comparisonData = await comparisonRequest;
        this.comparisonData =
          this.data?.count > this.aggregatedPageSize ? undefined : comparisonData;
        this.comparisonPending = false;

        this.trackRender();
      } catch (error) {
        // Keep the parsed config through the failure: consumers size their error
        // states by the display type, which the query still declares.
        const { config } = this;

        this.resetData();
        this.config = config;
        this.error = error;
      } finally {
        this.loading = false;
        this.comparisonPending = false;
        this.emitChange();
      }
    },

    // Its `limit` variable stays null on purpose: the compiler never fills it and only the main
    // query gets the `limit:` config, so the backend serves its default page of `aggregatedPageSize`
    // rows and a `limit: 5` table still pairs rows on its later pages. `executeQuery` drops the
    // comparison past that size, since one page then cannot pair every row. Never rejects.
    async fetchComparison() {
      if (!this.comparison?.query) return undefined;

      try {
        const { query, variables, fields, mode, source } = await parse(
          this.comparison.query,
          this.scope,
          { bindings: this.comparison.bindings ?? this.bindings },
        );
        const executionResult = await execute(query, variables, {
          queue: this.queue,
          priority: this.priority,
          signal: this.abortController.signal,
          tag: this.glqlQuery,
        });
        const result = await transform(executionResult, { fields, mode, source });

        return { ...result, metric: this.comparison.metric };
      } catch (error) {
        // Skip only the queue's own abort rejection, so real failures after teardown still report.
        if (error === this.abortController.signal.reason) return undefined;

        Sentry.captureException(error);
        return undefined;
      }
    },

    // Runs the parsed query again with the variables as they stand, so a page fetch carries
    // the cursor `setVariable('after', ...)` placed there.
    async fetchPage() {
      const executionResult = await execute(this.query, this.variables, {
        queue: this.queue,
        priority: this.priority,
        signal: this.abortController.signal,
        tag: this.glqlQuery,
      });

      return transform(executionResult, {
        fields: this.fields,
        mode: this.mode,
        source: this.source,
      });
    },

    async fetchNextPage() {
      const data = await this.fetchPage();

      this.data = {
        ...this.data,
        pageInfo: data.pageInfo,
        nodes: [...this.data.nodes, ...data.nodes],
      };
    },

    showPage(pageList) {
      const { nodes, pageInfo } = currentPage(pageList);
      this.pageList = pageList;
      this.data = { ...this.data, nodes, pageInfo };
      this.emitChange();
    },

    previousPage() {
      if (this.pageLoading) return;
      this.error = undefined;

      if (this.hasPreviousPage) this.showPage(goToPage(this.pageList, this.pageList.index - 1));
    },

    async nextPage() {
      if (this.pageLoading) return;
      // A failed turn is over once the user turns again; keeping it would hide the panel's
      // source actions and report the same error on every later change.
      this.error = undefined;

      if (hasCachedNextPage(this.pageList)) {
        this.showPage(goToPage(this.pageList, this.pageList.index + 1));
        return;
      }

      const after = this.data?.pageInfo?.endCursor;
      if (!after) {
        this.emitChange();
        return;
      }

      try {
        this.pageLoading = true;
        this.setVariable('after', after);

        const { nodes, pageInfo } = await this.fetchPage();

        if (!nodes?.length) {
          this.endOnCurrentPage();
          return;
        }

        this.showPage(appendPage(this.pageList, { nodes, pageInfo }));
      } catch (error) {
        // The page on screen is still good; only the turn failed.
        this.error = error;
        this.emitChange();
      } finally {
        this.pageLoading = false;
      }
    },

    // The data shrank between requests, so the page on screen is the last one now. Showing the
    // empty page would hand the dashboard an empty result and replace the table with its empty
    // state, which has no way back.
    endOnCurrentPage() {
      this.showPage(markCurrentPageAsLast(this.pageList));
    },

    // Emits nothing: the caller emits once, so the chart never draws a partial aggregate.
    async autoPaginate() {
      if (!this.data?.nodes) return;

      // Bounds requests as well as rows, so a backend that keeps claiming another page can't spin.
      const maxPages = Math.ceil(MAX_AUTO_PAGINATED_ROWS / this.aggregatedPageSize);

      for (let page = 0; page < maxPages; page += 1) {
        if (this.discarded) return;

        const after = this.data.pageInfo?.endCursor;
        if (!after || !this.data.pageInfo.hasNextPage) break;
        if (this.data.nodes.length >= MAX_AUTO_PAGINATED_ROWS) break;

        this.setVariable('after', after);

        try {
          // Sequential by nature: each request needs the previous page's cursor.
          // eslint-disable-next-line no-await-in-loop
          await this.fetchNextPage();
        } catch (error) {
          if (this.discarded) return;

          // Rate limiting is keyed by query SHA, so once a page fails the next is rejected too.
          // Keep the pages already loaded rather than losing the chart. TODO: warn that the view
          // is incomplete — https://gitlab.com/gitlab-org/glql/-/work_items/216
          Sentry.captureException(error);
          break;
        }
      }

      // Every exit above can leave rows behind, not just the row cap: a short page, a missing
      // cursor, or a failed continuation. Compare against the total rather than track each one.
      this.resultsTruncated = Boolean(this.data?.count && this.data.nodes.length < this.data.count);
    },

    async loadMore() {
      try {
        this.setVariable('after', this.data.pageInfo?.endCursor);
        this.loading = true;
        this.emitChange();

        await this.fetchNextPage();
      } catch (error) {
        this.error = error;
      } finally {
        this.loading = false;
        this.emitChange();
      }
    },

    async trackRender() {
      if (!this.trackingEventName) return;

      try {
        this.trackEvent(this.trackingEventName, { label: await sha256(this.glqlQuery) });
      } catch (e) {
        // ignore any tracking errors
      }
    },

    handlePresenterError(error) {
      // The presenter cannot render these rows, so there is nothing worth keeping on screen.
      this.data = undefined;
      this.error = error;
      this.emitChange();
    },
  },
};
</script>
<template>
  <!-- A paged table fills its panel and keeps the controls at the bottom, so turning to a
       shorter page does not move them. -->
  <div :class="{ 'gl-flex gl-h-full gl-flex-col': isPaged }">
    <!-- An error with rows already loaded (a failed continuation page) keeps them visible. -->
    <data-presenter
      v-if="hasDisplayType && (data || !error)"
      :data="data"
      :comparison-data="comparisonData"
      :comparison-pending="comparisonPending"
      :comparison-metric="comparison?.metric ?? null"
      :fields="fields"
      :display-type="config.display"
      :display-config="config.displayConfig"
      :source="source"
      :loading="loading"
      :display-page-size="displayPageSize"
      @error="handlePresenterError"
    />
    <div
      v-if="hasNextPage && pagination === $options.PAGINATION_LOAD_MORE"
      class="glql-load-more gl-border-t gl-p-3"
    >
      <glql-pagination
        :count="data.nodes.length"
        :total-count="data.count"
        :page-size="variables.limit.value"
        :loading="loading"
        @load-more="loadMore"
      />
    </div>
    <div
      v-else-if="isPaged && (hasPreviousPage || hasNextPage)"
      class="glql-load-more gl-border-t gl-mt-auto gl-flex gl-items-center gl-justify-between gl-p-3"
    >
      <gl-keyset-pagination
        :has-previous-page="hasPreviousPage"
        :has-next-page="hasNextPage"
        :disabled="pageLoading"
        @prev="previousPage"
        @next="nextPage"
      />
      <span v-if="pageCounter" class="gl-text-sm gl-text-subtle" data-testid="page-counter">{{
        pageCounter
      }}</span>
    </div>
  </div>
</template>
