import { s__ } from '~/locale';
import { getUniquePanelId } from '~/explore/analytics_dashboards/utils';
import { parseYAML } from '~/glql/core/parser';

export const wrapGlqlInVisualization = (glql) => ({
  type: 'Glql',
  options: {},
  data: {
    type: 'glql',
    query: {
      glql,
    },
  },
});

// Reads the `title` from a GLQL query's frontmatter, falling back to a default
// when the query does not define one or its frontmatter is malformed.
export const parseGlqlTitle = (glql) => {
  const defaultPanelTitle = s__('AnalyticsDashboards|Untitled');
  try {
    const { config } = parseYAML(glql);
    return config.title || defaultPanelTitle;
  } catch {
    return defaultPanelTitle;
  }
};

export const wrapVisualizationInPanel = (visualization, title) => ({
  id: getUniquePanelId(),
  title,
  visualization,
  gridAttributes: {
    width: 6,
    height: 41,
  },
});

// Serializes the in-memory dashboard panels into the shape accepted by the
// updateCustomDashboard mutation: the client-only `id` and `loadPriority` are dropped and
// the visualization is sent as the JSON visualizationConfig field.
export const serializePanelsForMutation = (panels = []) =>
  panels.map(({ id, loadPriority, visualization, ...panel }) => ({
    ...panel,
    visualizationConfig: visualization,
  }));
