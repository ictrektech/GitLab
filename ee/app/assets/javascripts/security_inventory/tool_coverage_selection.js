import { snakeCase } from 'lodash-es';
import {
  ALL_SCANNERS_KEY,
  ANALYZER_KEYS,
  STATUS_KEY,
  STATUS_FILTER_TO_TOOL_STATUS,
} from './constants';
import { hasFilterData } from './filter_url_sync';
import { visibleScannerGroups } from './utils';

const STATUS_PARAM = snakeCase(STATUS_KEY);

const NO_SELECTION = { scanner: ALL_SCANNERS_KEY, status: null };

const SCANNER_PARAM_TO_KEY = Object.fromEntries(ANALYZER_KEYS.map((key) => [snakeCase(key), key]));

const CARD_PARAMS = [STATUS_PARAM, ...Object.keys(SCANNER_PARAM_TO_KEY)];

const TOOL_STATUS_TO_STATUS_FILTER = Object.fromEntries(
  Object.entries(STATUS_FILTER_TO_TOOL_STATUS).map(([filter, status]) => [status, filter]),
);

const toParamValue = (value) => String(value).toLowerCase();

const fromParamValue = (param) => String(param).toUpperCase();

const isCardStatus = (status) => status in TOOL_STATUS_TO_STATUS_FILTER;

// Flag-gated scanners drop out of visibleScannerGroups(), so their params are ignored too. Tiles
// and their sub-scanners are both selectable, so both have to count as visible.
const visibleScanners = () =>
  Object.entries(visibleScannerGroups()).flatMap(([tile, subScanners]) => [tile, ...subScanners]);

const isHiddenParam = (key) => {
  const scanner = SCANNER_PARAM_TO_KEY[key];

  return Boolean(scanner) && !visibleScanners().includes(scanner);
};

const activeCardParams = (params) =>
  Object.entries(params).filter(
    ([key, value]) => CARD_PARAMS.includes(key) && !isHiddenParam(key) && hasFilterData(value),
  );

const clearedCardParams = () => Object.fromEntries(CARD_PARAMS.map((key) => [key, null]));

export const cardSelectionFromParams = (params = {}) => {
  const [onlyCardParam, ...furtherCardParams] = activeCardParams(params);
  if (!onlyCardParam || furtherCardParams.length) return NO_SELECTION;

  const [key, param] = onlyCardParam;
  const paramValue = fromParamValue(param);

  if (key === STATUS_PARAM) {
    const statusForAllScanners = STATUS_FILTER_TO_TOOL_STATUS[paramValue];

    return statusForAllScanners
      ? { scanner: ALL_SCANNERS_KEY, status: statusForAllScanners }
      : NO_SELECTION;
  }

  return isCardStatus(paramValue)
    ? { scanner: SCANNER_PARAM_TO_KEY[key], status: paramValue }
    : NO_SELECTION;
};

export const paramsFromCardSelection = ({ scanner, status } = {}) => {
  if (!isCardStatus(status)) return clearedCardParams();

  if (scanner === ALL_SCANNERS_KEY) {
    const statusFilter = TOOL_STATUS_TO_STATUS_FILTER[status];

    return { ...clearedCardParams(), [STATUS_PARAM]: toParamValue(statusFilter) };
  }

  return SCANNER_PARAM_TO_KEY[snakeCase(scanner)]
    ? { ...clearedCardParams(), [snakeCase(scanner)]: toParamValue(status) }
    : clearedCardParams();
};
