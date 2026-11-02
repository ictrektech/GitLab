import { GlTableLite } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import CapabilityPanel from 'ee/admin/subscriptions/billable_usage_report/components/capability_panel.vue';

const capability = ({ name, meteringUnit = 'Request', quantity, isSnapshot = false }) => ({
  key: name,
  name,
  meteringUnit,
  quantity,
  isSnapshot,
});

describe('CapabilityPanel', () => {
  let wrapper;

  // Mounted rather than shallow-mounted: the table rendering and the footer note are the
  // behaviour under test, and a stub would report them as present without rendering them.
  const createComponent = (panel) => {
    wrapper = mountExtended(CapabilityPanel, { propsData: { panel } });
  };

  const findTotal = () => wrapper.findByTestId('capability-total');
  const findSnapshotNote = () => wrapper.findByTestId('snapshot-note');
  const rowTexts = () =>
    wrapper
      .findComponent(GlTableLite)
      .findAll('tbody tr')
      .wrappers.map((row) => row.findAll('td').wrappers.map((cell) => cell.text()));

  it('titles the panel after the product and formats the total', () => {
    createComponent({
      product: 'Secrets Manager',
      totalBillableEvents: 1023694,
      capabilities: [capability({ name: 'Secrets Read', quantity: 1023694 })],
    });

    expect(wrapper.text()).toContain('Secrets Manager');
    expect(findTotal().text()).toBe('1,023,694 total billable events');
  });

  it('uses the singular when the total is one', () => {
    createComponent({
      product: 'Secrets Manager',
      totalBillableEvents: 1,
      capabilities: [capability({ name: 'Secrets Read', quantity: 1 })],
    });

    expect(findTotal().text()).toBe('1 total billable event');
  });

  it('renders a row per meter with the quantity formatted', () => {
    createComponent({
      product: 'Duo Agent Platform',
      totalBillableEvents: 1004,
      capabilities: [
        capability({ name: 'Agentic Chat', meteringUnit: 'Model call', quantity: 1000 }),
        capability({ name: 'Code Review Flow', meteringUnit: 'Execution', quantity: 4 }),
      ],
    });

    expect(rowTexts()).toEqual([
      ['Agentic Chat', 'Model call', '1,000'],
      ['Code Review Flow', 'Execution', '4'],
    ]);
  });

  it('renders no footer note when nothing is a snapshot', () => {
    createComponent({
      product: 'Secrets Manager',
      totalBillableEvents: 10,
      capabilities: [capability({ name: 'Secrets Read', quantity: 10 })],
    });

    expect(findSnapshotNote().exists()).toBe(false);
  });

  it('names a single snapshot meter in the footer', () => {
    createComponent({
      product: 'Secrets Manager',
      totalBillableEvents: 10,
      capabilities: [
        capability({ name: 'Secrets Read', quantity: 10 }),
        capability({ name: 'Secrets Stored', quantity: 40, isSnapshot: true }),
      ],
    });

    expect(findSnapshotNote().text()).toBe(
      'Excluded from the total (month-end counts, not billable events): Secrets Stored',
    );
  });

  // A product can hold more than one point-in-time meter, and each is excluded from the
  // total, so naming only the first would leave the rest unexplained.
  it('names every snapshot meter in the footer', () => {
    createComponent({
      product: 'Artifact Registry',
      totalBillableEvents: 5,
      capabilities: [
        capability({ name: 'Artifact Registry Egress', meteringUnit: 'Gigabyte', quantity: 5 }),
        capability({ name: 'Artifact Registry Storage', quantity: 40, isSnapshot: true }),
        capability({ name: 'Artifact Registry Components', quantity: 12, isSnapshot: true }),
      ],
    });

    expect(findSnapshotNote().text()).toBe(
      'Excluded from the total (month-end counts, not billable events): Artifact Registry Storage and Artifact Registry Components',
    );
  });

  it('renders a zero total rather than omitting it', () => {
    createComponent({
      product: 'Artifact Registry',
      totalBillableEvents: 0,
      capabilities: [
        capability({ name: 'Artifact Registry Storage', quantity: 9, isSnapshot: true }),
      ],
    });

    expect(findTotal().text()).toBe('0 total billable events');
  });
});
