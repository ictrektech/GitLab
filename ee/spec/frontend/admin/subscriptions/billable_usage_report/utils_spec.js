import {
  buildCapabilityPanels,
  summariseSeatLink,
  noDataDates,
  noDataRanges,
} from 'ee/admin/subscriptions/billable_usage_report/utils';

const record = ({ fqn, unit = 'request', quantity, kind = 'counter', product }) => ({
  event_type: fqn,
  unit_of_measure: unit,
  quantity,
  metadata: { feature_qualified_name: fqn, quantity_kind: kind, ...(product && { product }) },
});

describe('buildCapabilityPanels', () => {
  it('returns no panels for an empty report', () => {
    expect(buildCapabilityPanels([])).toEqual([]);
    expect(buildCapabilityPanels()).toEqual([]);
  });

  it('sums a meter across days into one row', () => {
    const [panel] = buildCapabilityPanels([
      record({ fqn: 'secrets_read', quantity: 100 }),
      record({ fqn: 'secrets_read', quantity: 23 }),
    ]);

    expect(panel.product).toBe('Secrets Manager');
    expect(panel.capabilities).toEqual([
      {
        key: 'secrets_read',
        name: 'Secrets Read',
        meteringUnit: 'Request',
        quantity: 123,
        isSnapshot: false,
      },
    ]);
  });

  it('groups meters of the same product into one panel', () => {
    const panels = buildCapabilityPanels([
      record({ fqn: 'secrets_read', quantity: 10 }),
      record({ fqn: 'secrets_stored', unit: 'secret', quantity: 7, kind: 'snapshot' }),
    ]);

    expect(panels.map((panel) => panel.product)).toEqual(['Secrets Manager']);
    expect(panels[0].capabilities).toHaveLength(2);
  });

  // CustomersDot prices on the first `/` segment, so the UI groups on it too. Two
  // versions of one meter are one capability, not two.
  it('groups a qualified feature name by its workflow', () => {
    const [panel] = buildCapabilityPanels([
      record({ fqn: 'code_review/v1', unit: 'execution', quantity: 400 }),
      record({ fqn: 'code_review/v2', unit: 'execution', quantity: 600 }),
    ]);

    expect(panel.product).toBe('Duo Agent Platform');
    expect(panel.totalBillableEvents).toBe(1000);
    expect(panel.capabilities).toEqual([
      {
        key: 'code_review',
        name: 'Code Review Flow',
        meteringUnit: 'Execution',
        quantity: 1000,
        isSnapshot: false,
      },
    ]);
  });

  it('groups Duo Agent Platform workflows into one panel', () => {
    const panels = buildCapabilityPanels([
      record({ fqn: 'software_development', unit: 'token', quantity: 10 }),
      record({ fqn: 'code_review', unit: 'token', quantity: 5 }),
      record({ fqn: 'secrets_read', quantity: 1 }),
    ]);

    expect(panels.map((panel) => panel.product)).toEqual(['Duo Agent Platform', 'Secrets Manager']);
    expect(panels[0].capabilities.map((row) => row.name)).toEqual([
      'Software Development Flow',
      'Code Review Flow',
    ]);
  });

  it('prefers a product named by the payload over the catalog', () => {
    const panels = buildCapabilityPanels([
      record({ fqn: 'secrets_read', quantity: 10, product: 'Renamed Product' }),
    ]);

    expect(panels.map((panel) => panel.product)).toEqual(['Renamed Product']);
  });

  // A meter nobody has named must never join another product's total. It gets its own
  // panel, so a new product renders correctly before the catalog or the payload knows it.
  it('gives an unknown meter its own panel, not another product total', () => {
    const panels = buildCapabilityPanels([
      record({ fqn: 'secrets_read', quantity: 10 }),
      record({ fqn: 'duo_agent_platform_workflow_completion', quantity: 400 }),
    ]);

    expect(panels.map((panel) => [panel.product, panel.totalBillableEvents])).toEqual([
      ['Secrets Manager', 10],
      ['Duo agent platform workflow completion', 400],
    ]);
  });

  // The prototype's own Duo Agent Platform panel mixes model calls with executions and
  // still totals them: every counter is a count of events, whatever the unit is called.
  // Only snapshots are excluded, on `quantity_kind`.
  it('totals a product whose meters describe their units differently', () => {
    const [panel] = buildCapabilityPanels([
      record({ fqn: 'software_development', unit: 'model_call', quantity: 900 }),
      record({ fqn: 'code_review', unit: 'execution', quantity: 4 }),
    ]);

    expect(panel.product).toBe('Duo Agent Platform');
    expect(panel.totalBillableEvents).toBe(904);
  });

  it('lists a snapshot meter but leaves it out of the product total', () => {
    const [panel] = buildCapabilityPanels([
      record({ fqn: 'secrets_read', quantity: 100 }),
      record({ fqn: 'secrets_stored', unit: 'secret', quantity: 40, kind: 'snapshot' }),
    ]);

    expect(panel.totalBillableEvents).toBe(100);
    expect(panel.capabilities).toHaveLength(2);
    expect(panel.capabilities[1]).toMatchObject({ name: 'Secrets Stored', isSnapshot: true });
  });

  it('excludes a snapshot the catalog has never heard of', () => {
    const [panel] = buildCapabilityPanels([
      record({ fqn: 'artifact_registry_stored', unit: 'byte', quantity: 500, kind: 'snapshot' }),
      record({ fqn: 'artifact_registry_stored', unit: 'byte', quantity: 500, kind: 'snapshot' }),
    ]);

    expect(panel.totalBillableEvents).toBe(0);
    expect(panel.capabilities[0]).toMatchObject({ quantity: 1000, isSnapshot: true });
  });

  it('falls back to humanized names for a meter it does not know', () => {
    const [panel] = buildCapabilityPanels([
      record({ fqn: 'some_new_flow', unit: 'model_call', quantity: 3 }),
    ]);

    expect(panel.product).toBe('Some new flow');
    expect(panel.totalBillableEvents).toBe(3);
    expect(panel.capabilities[0]).toMatchObject({
      name: 'Some new flow',
      meteringUnit: 'Model call',
    });
  });

  it('treats a record with no metadata as unknown rather than throwing', () => {
    const [panel] = buildCapabilityPanels([{ unit_of_measure: 'request', quantity: 2 }]);

    expect(panel.product).toBe('');
    expect(panel.capabilities[0]).toMatchObject({ name: '', meteringUnit: 'Request' });
  });
});

describe('summariseSeatLink', () => {
  it('zeroes every figure when the series is empty', () => {
    expect(summariseSeatLink([])).toEqual({
      recordCount: 0,
      highestBillableUsers: 0,
      billableUsersOnLastDay: 0,
    });
    expect(summariseSeatLink()).toEqual({
      recordCount: 0,
      highestBillableUsers: 0,
      billableUsersOnLastDay: 0,
    });
  });

  it('takes the maximum and the final day from the series', () => {
    expect(
      summariseSeatLink([
        { date: '2026-08-01', billable_user_count: 412 },
        { date: '2026-08-02', billable_user_count: 438 },
        { date: '2026-08-03', billable_user_count: 420 },
      ]),
    ).toEqual({ recordCount: 3, highestBillableUsers: 438, billableUsersOnLastDay: 420 });
  });
});

describe('noDataDates', () => {
  it('is empty when coverage is absent or complete', () => {
    expect(noDataDates()).toEqual([]);
    expect(noDataDates({ seat_link: {} })).toEqual([]);
  });

  // billable_events carries no no_data_dates by design: a missing usage row cannot
  // distinguish "no usage" from "nothing recorded", so only seat link proves absence.
  it('reports seat link gaps, sorted, and ignores billable_events', () => {
    expect(
      noDataDates({
        seat_link: { no_data_dates: ['2026-08-03', '2026-08-01'] },
        billable_events: { included: true, days_with_data: 20 },
      }),
    ).toEqual(['2026-08-01', '2026-08-03']);
  });
});

describe('noDataRanges', () => {
  it('is empty when nothing is missing', () => {
    expect(noDataRanges([])).toEqual([]);
    expect(noDataRanges()).toEqual([]);
  });

  it('keeps a single day as its own run', () => {
    expect(noDataRanges(['2026-08-01'])).toEqual([{ start: '2026-08-01', end: '2026-08-01' }]);
  });

  it('collapses consecutive days into one run', () => {
    expect(noDataRanges(['2026-08-01', '2026-08-02', '2026-08-03'])).toEqual([
      { start: '2026-08-01', end: '2026-08-03' },
    ]);
  });

  it('starts a new run across a gap', () => {
    expect(noDataRanges(['2026-08-01', '2026-08-02', '2026-08-04'])).toEqual([
      { start: '2026-08-01', end: '2026-08-02' },
      { start: '2026-08-04', end: '2026-08-04' },
    ]);
  });

  it('joins runs across month and year boundaries', () => {
    expect(noDataRanges(['2026-01-31', '2026-02-01'])).toEqual([
      { start: '2026-01-31', end: '2026-02-01' },
    ]);
    expect(noDataRanges(['2025-12-31', '2026-01-01'])).toEqual([
      { start: '2025-12-31', end: '2026-01-01' },
    ]);
  });

  // Day numbers are derived in UTC, so a local daylight-saving transition inside the run
  // cannot make two adjacent days look like anything other than one apart.
  it('joins a run spanning a daylight-saving transition', () => {
    expect(noDataRanges(['2026-03-28', '2026-03-29', '2026-03-30'])).toEqual([
      { start: '2026-03-28', end: '2026-03-30' },
    ]);
  });
});
