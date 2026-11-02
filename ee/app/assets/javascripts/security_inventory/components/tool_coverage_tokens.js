import { s__ } from '~/locale';
import { OPERATORS_IS } from '~/vue_shared/components/filtered_search_bar/constants';
import BaseToken from '~/vue_shared/components/filtered_search_bar/tokens/base_token.vue';
import {
  SCANNER_FILTER_LABELS,
  SCANNER_SEGMENT_LABELS,
  DEPENDENCY_SCANNING_KEY,
  SAST_KEY,
  SAST_ADVANCED_KEY,
  SECRET_DETECTION_KEY,
  SECRET_DETECTION_PIPELINE_BASED_KEY,
  SECRET_PUSH_PROTECTION_KEY,
  CONTAINER_SCANNING_KEY,
  CONTAINER_SCANNING_FOR_REGISTRY_KEY,
  DAST_KEY,
  SAST_IAC_KEY,
  TOOL_FILTER_LABELS,
  TOOL_ENABLED,
  TOOL_NOT_ENABLED,
  TOOL_FAILED,
  TOOL_STALE,
  BUSINESS_LOGIC_KEY,
  SKILLGUARD_KEY,
} from '../constants';
import { visibleScannerGroups } from '../utils';

const options = [
  { value: TOOL_ENABLED, title: TOOL_FILTER_LABELS[TOOL_ENABLED] },
  { value: TOOL_NOT_ENABLED, title: TOOL_FILTER_LABELS[TOOL_NOT_ENABLED] },
  { value: TOOL_FAILED, title: TOOL_FILTER_LABELS[TOOL_FAILED] },
  { value: TOOL_STALE, title: TOOL_FILTER_LABELS[TOOL_STALE] },
];

// Business logic scanning and SkillGuard are each behind a flag, same as their coverage groups.
const isBusinessLogicVisible = () => BUSINESS_LOGIC_KEY in visibleScannerGroups();
const isSkillguardVisible = () => SKILLGUARD_KEY in visibleScannerGroups();

const showWhenAnyItemMatches = ({ query, title, defaultMatcher }) =>
  [
    title,
    SCANNER_FILTER_LABELS[DEPENDENCY_SCANNING_KEY],
    SCANNER_FILTER_LABELS[SAST_KEY],
    SCANNER_FILTER_LABELS[SAST_ADVANCED_KEY],
    SCANNER_FILTER_LABELS[SECRET_DETECTION_KEY],
    SCANNER_FILTER_LABELS[SECRET_DETECTION_PIPELINE_BASED_KEY],
    SCANNER_FILTER_LABELS[SECRET_PUSH_PROTECTION_KEY],
    SCANNER_FILTER_LABELS[CONTAINER_SCANNING_KEY],
    SCANNER_FILTER_LABELS[CONTAINER_SCANNING_FOR_REGISTRY_KEY],
    SCANNER_FILTER_LABELS[DAST_KEY],
    SCANNER_FILTER_LABELS[SAST_IAC_KEY],
    ...(isBusinessLogicVisible() ? [SCANNER_FILTER_LABELS[BUSINESS_LOGIC_KEY]] : []),
    ...(isSkillguardVisible() ? [SCANNER_FILTER_LABELS[SKILLGUARD_KEY]] : []),
  ].some((keyword) => defaultMatcher(keyword, query));

export const toolCoverageTokens = [
  {
    type: 'gl-filtered-search-suggestion-group-tool-coverage',
    title: s__('SecurityInventory|Tool coverage'),
    match: showWhenAnyItemMatches,
  },
  {
    type: DEPENDENCY_SCANNING_KEY,
    title: SCANNER_FILTER_LABELS[DEPENDENCY_SCANNING_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[DEPENDENCY_SCANNING_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
  {
    type: SAST_KEY,
    title: SCANNER_FILTER_LABELS[SAST_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[SAST_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
  {
    type: SAST_ADVANCED_KEY,
    title: SCANNER_FILTER_LABELS[SAST_ADVANCED_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[SAST_ADVANCED_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
  {
    type: SECRET_DETECTION_KEY,
    title: SCANNER_FILTER_LABELS[SECRET_DETECTION_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[SECRET_DETECTION_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
  {
    type: SECRET_DETECTION_PIPELINE_BASED_KEY,
    title: SCANNER_FILTER_LABELS[SECRET_DETECTION_PIPELINE_BASED_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[SECRET_DETECTION_PIPELINE_BASED_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
  {
    type: SECRET_PUSH_PROTECTION_KEY,
    title: SCANNER_FILTER_LABELS[SECRET_PUSH_PROTECTION_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[SECRET_PUSH_PROTECTION_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
  {
    type: CONTAINER_SCANNING_KEY,
    title: SCANNER_FILTER_LABELS[CONTAINER_SCANNING_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[CONTAINER_SCANNING_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
  {
    type: CONTAINER_SCANNING_FOR_REGISTRY_KEY,
    title: SCANNER_FILTER_LABELS[CONTAINER_SCANNING_FOR_REGISTRY_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[CONTAINER_SCANNING_FOR_REGISTRY_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
  {
    type: DAST_KEY,
    title: SCANNER_FILTER_LABELS[DAST_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[DAST_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
  {
    type: SAST_IAC_KEY,
    title: SCANNER_FILTER_LABELS[SAST_IAC_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[SAST_IAC_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
  {
    type: BUSINESS_LOGIC_KEY,
    title: SCANNER_FILTER_LABELS[BUSINESS_LOGIC_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[BUSINESS_LOGIC_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
  {
    type: SKILLGUARD_KEY,
    title: SCANNER_FILTER_LABELS[SKILLGUARD_KEY],
    segmentTitle: SCANNER_SEGMENT_LABELS[SKILLGUARD_KEY],
    token: BaseToken,
    unique: true,
    operators: OPERATORS_IS,
    options,
  },
];

export const visibleToolCoverageTokens = () => {
  const hidden = [];

  if (!isBusinessLogicVisible()) hidden.push(BUSINESS_LOGIC_KEY);
  if (!isSkillguardVisible()) hidden.push(SKILLGUARD_KEY);

  return hidden.length
    ? toolCoverageTokens.filter(({ type }) => !hidden.includes(type))
    : toolCoverageTokens;
};
