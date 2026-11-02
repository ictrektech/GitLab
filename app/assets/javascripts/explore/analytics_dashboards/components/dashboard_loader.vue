<script>
import { GlSkeletonLoader, GlAlert, GlEmptyState } from '@gitlab/ui';
import { isPlainObject } from 'lodash-es';
import { s__ } from '~/locale';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import { RESOURCE_ACCESS_ERROR } from '~/graphql_shared/constants';
import {
  FULL_DASHBOARD_WIDTH,
  GRID_HEIGHT_COMPACT_CELL_HEIGHT,
  GRID_HEIGHT_COMPACT_MIN_CELL_HEIGHT,
} from '../constants';
import {
  assignLoadPriority,
  convertToDashboardGraphQLId,
  getUniquePanelId,
  isSystemDashboardSlug,
} from '../utils';
import getDashboardQuery from '../graphql/get_dashboard.query.graphql';
import getSystemDashboardQuery from '../graphql/get_system_dashboard.query.graphql';

// What the API answers for a dashboard the user may not see, such as one behind a disabled
// feature flag or a missing licence. It is deliberately the same answer as for one that is missing.
const isResourceNotAvailable = ({ graphQLErrors = [] }) =>
  graphQLErrors.length > 0 &&
  graphQLErrors.every(({ message }) => message === RESOURCE_ACCESS_ERROR);

// The JSON pointer a schema error carries, e.g. "property '/views/0/panels/2/visualization/type'
// is not of type: string". Errors without a panel index stay dashboard-level only.
// The third group is a panel's own view (`/panels/N/views/K`), not a dashboard view.
const PANEL_POINTER = /^property '(?:\/views\/(\d+))?\/panels\/(\d+)(?:\/views\/(\d+))?(?:\/|')/;
const TOP_LEVEL_PANELS = 'panels';

export default {
  name: 'DashboardLoader',
  components: { GlSkeletonLoader, GlAlert, GlEmptyState },
  inject: ['breadcrumbState', 'exploreAnalyticsDashboardsPath'],
  emits: ['loaded'],
  i18n: {
    notFound: s__('Analytics|Dashboard not found'),
    notFoundDescription: s__('Analytics|No dashboard matches the specified URL path.'),
    notFoundActionBtn: s__('Analytics|View available dashboards'),
  },
  // Explore dashboards always use the compact grid; the `gridHeight` config value is ignored.
  cellHeight: GRID_HEIGHT_COMPACT_CELL_HEIGHT,
  minCellHeight: GRID_HEIGHT_COMPACT_MIN_CELL_HEIGHT,
  data() {
    return {
      dashboard: null,
      error: null,
    };
  },
  computed: {
    slug() {
      return this.$route?.params.slug;
    },
    isSystemDashboard() {
      return isSystemDashboardSlug(this.slug);
    },
    dashboardId() {
      return this.isSystemDashboard ? this.slug : convertToDashboardGraphQLId(this.slug);
    },
    isLoading() {
      return Boolean(this.$apollo.queries.dashboard?.loading);
    },
    isNotFound() {
      return !this.dashboard;
    },
    config() {
      if (!this.dashboard?.config) return {};
      // Each panel needs a uniqueId or the prop validator for GlDashboardLayout will fail.
      // A dashboard that failed schema validation may not even have a panels array.
      const { panels, views, ...rest } = this.dashboard.config;
      const schemaErrors = this.panelSchemaErrors();
      return {
        ...rest,
        // The API already falls back to the slug when the title is missing.
        title: rest.title || this.dashboard.name,
        panels: this.assignPanelIds(
          this.objectList(this.withSchemaErrors(panels, schemaErrors[TOP_LEVEL_PANELS])),
        ),
        ...(Array.isArray(views)
          ? {
              views: this.objectList(this.withViewSchemaErrors(views, schemaErrors)).map(
                (view) => ({
                  ...view,
                  panels: this.assignPanelIds(this.objectList(view.panels)),
                }),
              ),
            }
          : {}),
      };
    },
    errors() {
      return this.dashboard?.errors ?? [];
    },
  },
  watch: {
    dashboard() {
      if (!this.dashboard) return;

      this.breadcrumbState.update({ name: this.config.title, slug: this.slug });
      // Emit the processed config so consumers receive panels with unique ids,
      // matching what the slot-scoped config renders.
      this.$emit('loaded', JSON.parse(JSON.stringify({ ...this.dashboard, config: this.config })));
    },
  },
  methods: {
    // The breadcrumb state outlives this page, so it would otherwise keep the last dashboard's name.
    // Dashboard cleared so a slug changed in place does not keep showing the previous dashboard.
    showNotFound() {
      this.dashboard = null;
      this.breadcrumbState.update({ name: this.$options.i18n.notFound, slug: this.slug });
    },
    // Schema errors grouped by the raw list index their pointer names, so they are attached
    // before null entries are dropped and the indexes still line up.
    panelSchemaErrors() {
      return this.errors.reduce((byView, message) => {
        const match = PANEL_POINTER.exec(message);
        if (!match) return byView;

        const [, view = TOP_LEVEL_PANELS, panel, panelView] = match;
        const byPanel = byView[view] || {};
        const { all = [], viewErrorsByIndex = {} } = byPanel[panel] || {};
        const entry =
          panelView === undefined
            ? { all: [...all, message], viewErrorsByIndex }
            : {
                all,
                viewErrorsByIndex: {
                  ...viewErrorsByIndex,
                  [panelView]: [...(viewErrorsByIndex[panelView] || []), message],
                },
              };
        return { ...byView, [view]: { ...byPanel, [panel]: entry } };
      }, {});
    },
    // The shared panel alert renders `visualization.errors`, so a panel the schema rejected
    // shows its own error even when it has no visualization at all.
    withSchemaErrors(panels, errorsByIndex = {}) {
      if (!Array.isArray(panels)) return panels;

      return panels.map((panel, index) => {
        const { all = [], viewErrorsByIndex = {} } = errorsByIndex[index] || {};
        // A section renders its header instead of a visualization, so it has nowhere to show them.
        if (
          (!all.length && !Object.keys(viewErrorsByIndex).length) ||
          !isPlainObject(panel) ||
          panel.section
        ) {
          return panel;
        }

        // The panel renders the selected view's visualization when it has views, so a panel-wide
        // error goes on every view as well; a view's own error goes on that view only.
        const panelViews = Array.isArray(panel.views)
          ? panel.views.map((view, viewIndex) => {
              const viewErrors = [...(viewErrorsByIndex[viewIndex] || []), ...all];
              return isPlainObject(view) && viewErrors.length
                ? { ...view, visualization: this.withErrors(view.visualization, viewErrors) }
                : view;
            })
          : this.objectList(panel.views);

        return {
          ...panel,
          ...(all.length ? { visualization: this.withErrors(panel.visualization, all) } : {}),
          // The panel reads `views.length` and maps over it, so a scalar or null must not reach it.
          ...('views' in panel ? { views: panelViews } : {}),
        };
      });
    },
    // A rejected visualization, or its errors, may be a scalar, which must not be spread.
    withErrors(visualization, errors) {
      const base = isPlainObject(visualization) ? visualization : {};
      const existing = Array.isArray(base.errors) ? base.errors : [];
      return { ...base, errors: [...existing, ...errors] };
    },
    withViewSchemaErrors(views, schemaErrors) {
      return views.map((view, index) =>
        isPlainObject(view)
          ? { ...view, panels: this.withSchemaErrors(view.panels, schemaErrors[index]) }
          : view,
      );
    },
    // An unfinished YAML list item parses to null, which the schema reports and this skips.
    objectList(list) {
      return Array.isArray(list) ? list.filter((item) => item && typeof item === 'object') : [];
    },
    assignPanelIds(panels = []) {
      // The grid cannot place a panel or section without gridAttributes and throws on it.
      // The schema errors alert already reports the missing key.
      const placeable = panels.filter((panel) => isPlainObject(panel.gridAttributes));
      const withIds = placeable.map(({ id, ...panel }) => ({
        ...panel,
        // A section spans the dashboard, so its config omits a width. The grid
        // layout requires one, so fill it in here.
        ...(panel.section
          ? {
              gridAttributes: {
                width: FULL_DASHBOARD_WIDTH,
                ...panel.gridAttributes,
              },
            }
          : {}),
        id: getUniquePanelId(),
      }));

      // The grid slot drops `gridAttributes`, so each panel gets its load priority here, while
      // the position is still known.
      return assignLoadPriority(withIds);
    },
  },
  apollo: {
    dashboard: {
      query() {
        return this.isSystemDashboard ? getSystemDashboardQuery : getDashboardQuery;
      },
      variables() {
        if (this.isSystemDashboard) {
          return { slug: this.dashboardId };
        }
        return { id: this.dashboardId };
      },
      update({ customDashboard = {}, customSystemDashboard = {} }) {
        return this.isSystemDashboard ? customSystemDashboard : customDashboard;
      },
      result() {
        if (!this.dashboard) this.showNotFound();
      },
      error(err) {
        if (isResourceNotAvailable(err)) {
          this.showNotFound();
          return;
        }

        this.error = s__('AnalyticsDashboards|Failed to load dashboard. Please try again.');
        captureException(err);
      },
    },
  },
};
</script>
<template>
  <gl-skeleton-loader v-if="isLoading" class="gl-mt-5" />
  <gl-alert v-else-if="error" class="gl-mt-5" variant="danger" :dismissible="false">
    {{ error }}
  </gl-alert>
  <gl-empty-state
    v-else-if="isNotFound"
    :title="$options.i18n.notFound"
    :description="$options.i18n.notFoundDescription"
    :primary-button-text="$options.i18n.notFoundActionBtn"
    :primary-button-link="exploreAnalyticsDashboardsPath"
    illustration-name="empty-dashboard-md"
    data-testid="dashboard-not-found"
  />
  <div v-else>
    <slot
      name="dashboard"
      :dashboard-id="dashboardId"
      :config="config"
      :cell-height="$options.cellHeight"
      :min-cell-height="$options.minCellHeight"
      :is-system-dashboard="isSystemDashboard"
      :errors="errors"
    ></slot>
  </div>
</template>
