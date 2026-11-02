import { s__ } from '~/locale';

export const SCHEMA_DOMAINS = [
  { key: 'core', label: s__('Orbit|Core'), icon: 'project', entryType: 'project' },
  { key: 'plan', label: s__('Orbit|Work items'), icon: 'work-items', entryType: 'workitem' },
  {
    key: 'code_review',
    label: s__('Orbit|Merge requests'),
    icon: 'merge-request',
    entryType: 'mergerequest',
  },
  { key: 'ci', label: s__('Orbit|Pipelines'), icon: 'pipeline', entryType: 'pipeline' },
  { key: 'source_code', label: s__('Orbit|Code'), icon: 'code', entryType: 'file' },
  {
    key: 'security',
    label: s__('Orbit|Vulnerabilities'),
    icon: 'shield',
    entryType: 'vulnerability',
  },
  { key: 'packages', label: s__('Orbit|Packages'), icon: 'package', entryType: 'package' },
  {
    key: 'container_registry',
    label: s__('Orbit|Container registry'),
    icon: 'container-image',
    entryType: 'containerrepository',
  },
  { key: 'agents', label: s__('Orbit|AI agents'), icon: 'tanuki-ai', entryType: 'agentsession' },
];

// The ontology gives almost every entity type this relationship, so the UI treats it as a scope.
export const SCOPE_ENTITY = 'Project';
export const SCOPE_RELATIONSHIP = 'IN_PROJECT';

export const CLUSTER_CELL_WIDTH_PX = 170;
export const CLUSTER_CELL_HEIGHT_PX = 110;
export const CLUSTER_GAP_PX = 30;
export const RING_ASPECT_RATIO = 0.6;
export const RING_STEP_PX = 10;
export const CLUSTER_WIDTH_FACTOR = 1.5;
export const GRAPH_MARGIN_X_PX = 90;
export const GRAPH_MARGIN_Y_PX = 50;

export const NODE_RADIUS_PX = 20;
export const SCOPE_NODE_RADIUS_PX = 32;
export const EDGE_GAP_PX = 4;

export const MIN_GRAPH_SCALE = 0.7;
export const MAX_GRAPH_SCALE = 1.4;
export const ZOOM_STEP = 0.15;

export const EDGE_STAGGER_MS = 25;
export const MAX_EDGE_DELAY_MS = 300;
