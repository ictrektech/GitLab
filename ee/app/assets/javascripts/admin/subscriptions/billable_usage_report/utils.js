import { getDayDifference, newDate } from '~/lib/utils/datetime_utility';
import { humanize } from '~/lib/utils/text_utility';
import { FLOW_TYPES, QUANTITY_KIND_SNAPSHOT } from './constants';

const workflowOf = (featureQualifiedName) => String(featureQualifiedName ?? '').split('/')[0];

const meterFor = (workflow, unitOfMeasure) => ({
  capability: FLOW_TYPES[workflow]?.title ?? humanize(workflow),
  product: FLOW_TYPES[workflow]?.product,
  meteringUnit: humanize(unitOfMeasure ?? ''),
});

const panelNameFor = (record, meter) =>
  record.metadata?.product ?? meter.product ?? meter.capability;

/**
 * Collapses the export's flat daily records into one panel per product.
 *
 * `records[]` carries one entry per day per meter. A record whose `metadata.quantity_kind`
 * is a snapshot is listed but kept out of the product total: it is a point-in-time
 * reading, so summing a period's readings would not mean anything.
 *
 * @param {Array} records - the `records` array from the export payload
 * @returns {Array} panels, each `{ product, totalBillableEvents, capabilities }`
 */
export const buildCapabilityPanels = (records = []) => {
  const byProduct = new Map();

  records.forEach((record) => {
    const workflow = workflowOf(record.metadata?.feature_qualified_name);
    const meter = meterFor(workflow, record.unit_of_measure);
    const quantity = Number(record.quantity) || 0;
    const isSnapshot = record.metadata?.quantity_kind === QUANTITY_KIND_SNAPSHOT;
    const product = panelNameFor(record, meter);

    if (!byProduct.has(product)) {
      byProduct.set(product, { product, totalBillableEvents: 0, rows: new Map() });
    }

    const panel = byProduct.get(product);
    const existing = panel.rows.get(workflow);

    if (existing) {
      existing.quantity += quantity;
    } else {
      panel.rows.set(workflow, {
        key: workflow,
        name: meter.capability,
        meteringUnit: meter.meteringUnit,
        quantity,
        isSnapshot,
      });
    }

    if (!isSnapshot) {
      panel.totalBillableEvents += quantity;
    }
  });

  return [...byProduct.values()].map(({ product, totalBillableEvents, rows }) => ({
    product,
    totalBillableEvents,
    capabilities: [...rows.values()],
  }));
};

/**
 * @param {Array} records - `seat_link.records`, ordered by date ascending
 * @returns {Object} `{ recordCount, highestBillableUsers, billableUsersOnLastDay }`
 */
export const summariseSeatLink = (records = []) => {
  const counts = records.map((record) => record.billable_user_count);

  return {
    recordCount: records.length,
    highestBillableUsers: counts.length ? Math.max(...counts) : 0,
    billableUsersOnLastDay: counts.length ? counts[counts.length - 1] : 0,
  };
};

/**
 * Dates in the period where the instance recorded nothing.
 *
 * Only seat link can prove absence: it is written daily regardless of activity. A usage
 * row exists only once an event happens, so a day missing from `billable_events` proves
 * nothing and `coverage` deliberately reports only its count.
 *
 * @param {Object} coverage - the `coverage` block from the export payload
 * @returns {Array} sorted ISO dates
 */
export const noDataDates = (coverage = {}) => [...(coverage.seat_link?.no_data_dates ?? [])].sort();

/**
 * Collapses sorted ISO dates into consecutive runs, so a gap spanning a whole quarter
 * reads as one fact rather than ninety.
 *
 * @param {Array} dates - sorted ISO8601 calendar dates
 * @returns {Array} runs, each `{ start, end }`, with `end === start` for a single day
 */
export const noDataRanges = (dates = []) =>
  dates.reduce((runs, date) => {
    const current = runs[runs.length - 1];

    if (current && getDayDifference(newDate(current.end), newDate(date)) === 1) {
      current.end = date;

      return runs;
    }

    return [...runs, { start: date, end: date }];
  }, []);
