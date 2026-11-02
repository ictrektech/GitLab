import { PROMO_URL } from '~/constants';
import { s__ } from '~/locale';

export const STATUS_HEALTHY = 'HEALTHY';
export const STATUS_MIGRATING = 'MIGRATING';
export const STATUS_DEGRADED = 'DEGRADED';
export const STATUS_UNKNOWN = 'UNKNOWN';
export const ORBIT_SALES_URL = `${PROMO_URL}/sales/`;
export const RECENTLY_ENABLED_MS = 10 * 60 * 1000;
export const INDEXING_START_TIMEOUT_MS = 3 * 24 * 60 * 60 * 1000;

// `key` is the Orbit domain name.
export const ORBIT_AREAS = [
  { key: 'core', label: s__('Orbit|Core') },
  { key: 'plan', label: s__('Orbit|Planning') },
  { key: 'code_review', label: s__('Orbit|Code review') },
  { key: 'ci', label: s__('Orbit|CI/CD') },
  { key: 'source_code', label: s__('Orbit|Source code') },
  { key: 'security', label: s__('Orbit|Security') },
];

export const COMPONENT_LABELS = {
  schema_migration: s__('Orbit|Schema migration'),
  clickhouse: s__('Orbit|ClickHouse'),
  gitaly: s__('Orbit|Gitaly'),
};
export const TOON_BLOCK_PATTERN = /<toon>([\s\S]*?)<\/toon>/;

// --- Entity styling ---

// Backup colors used before the schema responds.
// Authoritative colors come from `Query.orbit.schema` (the GKG ontology YAML)
// and override these at runtime.
export const DEFAULT_NODE_COLOR = '#6B7280';
export const DEFAULT_ENTITY_COLOR = DEFAULT_NODE_COLOR;

export const ENTITY_TYPE_COLORS = {
  // core
  user: '#10B981',
  project: '#3B82F6',
  group: '#8B5CF6',
  note: '#64748B',
  // code_review
  mergerequest: '#F59E0B',
  mergerequestdiff: '#D97706',
  mergerequestdifffile: '#B45309',
  // ci
  pipeline: '#6366F1',
  stage: '#818CF8',
  job: '#8B5CF6',
  // security
  vulnerability: '#DC2626',
  vulnerabilityoccurrence: '#EF4444',
  finding: '#F87171',
  vulnerabilityscanner: '#FCA5A5',
  vulnerabilityidentifier: '#7F1D1D',
  securityscan: '#B91C1C',
  // plan
  workitem: '#EC4899',
  milestone: '#D946EF',
  label: '#A855F7',
  // source_code
  branch: '#14B8A6',
  file: '#22D3EE',
  directory: '#06B6D4',
  definition: '#2DD4BF',
  importedsymbol: '#5EEAD4',
  // code indexing subtypes (definition_type values, not separate ontology nodes)
  class: '#A78BFA',
  interface: '#A78BFA',
  enum: '#A855F7',
  method: '#EF4444',
  constructor: '#F97316',
  import: '#3B82F6',
  default: '#6B7280',
};

export const ENTITY_TYPE_NAMES = {
  group: s__('Orbit|Group'),
  user: s__('Orbit|User'),
  project: s__('Orbit|Project'),
  mergerequest: s__('Orbit|MergeRequest'),
  mergerequestdiff: s__('Orbit|MergeRequestDiff'),
  mergerequestdifffile: s__('Orbit|MergeRequestDiffFile'),
  note: s__('Orbit|Note'),
  pipeline: s__('Orbit|Pipeline'),
  stage: s__('Orbit|Stage'),
  job: s__('Orbit|Job'),
  workitem: s__('Orbit|WorkItem'),
  label: s__('Orbit|Label'),
  milestone: s__('Orbit|Milestone'),
  vulnerability: s__('Orbit|Vulnerability'),
  vulnerabilityoccurrence: s__('Orbit|VulnerabilityOccurrence'),
  vulnerabilityidentifier: s__('Orbit|VulnerabilityIdentifier'),
  vulnerabilityscanner: s__('Orbit|VulnerabilityScanner'),
  securityscan: s__('Orbit|SecurityScan'),
  finding: s__('Orbit|Finding'),
  file: s__('Orbit|File'),
  directory: s__('Orbit|Directory'),
  definition: s__('Orbit|Definition'),
  importedsymbol: s__('Orbit|ImportedSymbol'),
  branch: s__('Orbit|Branch'),
};

export const ENTITY_TYPE_ICONS = {
  group: 'group',
  project: 'project',
  user: 'user',
  note: 'comment',
  mergerequest: 'merge-request',
  mergerequestdiff: 'doc-code',
  mergerequestdifffile: 'file-modified',
  label: 'label',
  milestone: 'milestone',
  workitem: 'work-item-issue',
  pipeline: 'pipeline',
  stage: 'stage-all',
  job: 'settings',
  vulnerability: 'shield',
  vulnerabilityoccurrence: 'severity-unknown',
  vulnerabilityidentifier: 'hash',
  vulnerabilityscanner: 'search',
  finding: 'bug',
  securityscan: 'eye',
  branch: 'branch',
  commit: 'commit',
  deployment: 'deployments',
  environment: 'environment',
  runner: 'cloud-gear',
  containerrepository: 'container-image',
  package: 'package',
  packagefile: 'doc-text',
  dependency: 'link',
  file: 'document',
  directory: 'folder',
  definition: 'code',
  importedsymbol: 'import',
  agentsession: 'tanuki-ai',
};

// --- Domain styling ---

export const DOMAIN_COLORS = {
  core: '#6B7280',
  code_review: '#3B82F6',
  ci: '#F59E0B',
  security: '#EF4444',
  plan: '#8B5CF6',
  source_code: '#10B981',
};

// Invoked directly by name (node expansion supplies entity + node_ids per
// click), so it is not part of the fetched dropdown catalog.
export const NAMED_QUERY_EXPAND_NEIGHBORS = 'expand_neighbors';
export const NAMED_QUERY_LIST_NODES = 'list_nodes';

// Code intelligence panel queries, invoked directly by name with per-file or
// per-definition parameters.
export const NAMED_QUERY_FILE_DEFINITIONS = 'file_definitions';
export const NAMED_QUERY_FILE_DEFINITION_CALLERS = 'file_definition_callers';
export const NAMED_QUERY_DEFINITION_REFERENCES = 'definition_references';
export const NAMED_QUERY_DEFINITION_CALLEES = 'definition_callees';

// --- Graph rendering ---

export const GRAPH_DEFAULTS = {
  GLOBE_RADIUS: 5,
  NODE_HEIGHT: 1.06,
  ARC_MIN_HEIGHT: 1.1,
  CONNECTION_ARC_HEIGHT: 0.14,
  NODE_BASE_SIZE: 28,
  NODE_HOVER_EXTRA: 4,
  EDGE_OPACITY: 0.4,
  EDGE_CURVE_SEGMENTS: 50,
  HOVER_THRESHOLD: 0.05,
  CAMERA_FOV: 45,
  CAMERA_NEAR: 0.1,
  CAMERA_FAR: 1000,
  CAMERA_DEFAULT_Z: 15,
  CAMERA_MIN_ZOOM: 8,
  CAMERA_MAX_ZOOM: 25,
  CAMERA_2D_MIN_ZOOM: 1,
  CAMERA_2D_MAX_ZOOM: 300,
  BFS_OPACITY_DECAY: 0.2,
  BFS_MIN_OPACITY: 0.15,
  CLUSTER_SPREAD: 0.3,
  MIN_NODE_DISTANCE: 0.2,
  LAYOUT_ATTRACTION_ITERATIONS: 5,
  LAYOUT_REPULSION_ITERATIONS: 10,
  CAP_THETA_MIN: Math.PI / 6,
  CAP_THETA_MAX: Math.PI,
  CAP_N_LOW: 8,
  CAP_N_HIGH: 80,
  CAP_SPREAD_FLOOR: 0.35,
  BACK_LABEL_OPACITY: 0.1,
  BACK_FACE_FADE_LO: -0.05,
  BACK_FACE_FADE_HI: 0.15,
  ZOOM_LABEL_IN_FULL: 0.6,
  ZOOM_LABEL_OUT_HIDE: 2.0,
  ZOOM_LABEL_FADE_WIDTH: 0.2,
  CITY_LIGHT_COUNT: 8000,
  IDLE_TIMEOUT_MS: 3000,
  AUTO_ROTATE_SPEED: 0.0003,
  ANIMATION_SPEED: 0.2,
  CONNECTION_COLOR_DARK: 0xffa726,
  CONNECTION_COLOR_LIGHT: 0x6e5fb3,
  LIGHT_MODE_EDGE_OPACITY: 0.5,
  ARROW_OFFSET: 0.18,
  ARROW_RADIUS: 0.015,
  ARROW_HEIGHT: 0.04,
  ARROW_RADIAL_SEGMENTS: 4,
  ARROW_OPACITY_BOOST: 0.3,
  COUNTER_SCALE_MIN_FACTOR: 0.6,
};

// --- Code Navigation internal events ---

export const EVENT_OPEN_CODE_NAVIGATION_PANEL = 'open_code_navigation_panel';
export const EVENT_SELECT_CODE_NAVIGATION_SYMBOL = 'select_code_navigation_symbol';
export const EVENT_VIEW_CODE_NAVIGATION_TAB = 'view_code_navigation_tab';
export const EVENT_CLICK_JUMP_TO_DEFINITION = 'click_jump_to_definition_in_code_navigation';
