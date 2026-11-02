import { mountExtended } from 'helpers/vue_test_utils_helper';
import OffGroupsTable from 'ee/orbit/dashboard/off/off_groups_table.vue';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import { orbitPlatform } from '../../mock_data';

const buildRow = ({
  key = 'acme',
  namespaceId = 1,
  action = 'start_trial',
  offer = null,
  trialActive = false,
} = {}) => ({
  key,
  namespaceId,
  name: key,
  avatarUrl: null,
  action,
  offer,
  trialActive,
});

describe('OrbitOffGroupsTable', () => {
  let wrapper;

  const createComponent = ({ rows = [buildRow()], selected = [], saas = true } = {}) => {
    wrapper = mountExtended(OffGroupsTable, {
      propsData: { rows, selected },
      provide: { orbitPlatform: orbitPlatform({ saas }) },
    });
  };

  const findRow = (key) => wrapper.findByTestId(`orbit-off-row-${key}`);
  const findRowCheckbox = (key) => findRow(key).find('[data-testid="orbit-off-select-group"]');
  const findRowAvailability = (key) => findRow(key).find('[data-testid="orbit-off-availability"]');
  const findRowSales = (key) => findRow(key).findComponent(ContactSalesButton);
  const findSelectAll = () => wrapper.findByTestId('orbit-off-select-all');
  const findSelectAllInput = () => wrapper.find('thead input[type="checkbox"]');

  describe('with a group that starts a trial and a group that is not eligible', () => {
    beforeEach(() =>
      createComponent({
        rows: [
          buildRow({ key: 'acme', offer: { initialCredits: 100, durationDays: 30 } }),
          buildRow({ key: 'bank', namespaceId: 7, action: 'not_eligible' }),
        ],
        selected: ['acme'],
      }),
    );

    it('shows a checkbox only for the group that can turn on', () => {
      expect(findRowCheckbox('acme').attributes('aria-label')).toBe('acme');
      expect(findRowCheckbox('bank').exists()).toBe(false);
    });

    it('shows the offer for the trial group', () => {
      expect(findRowAvailability('acme').text()).toBe('100 credits when turned on');
    });

    it('shows why the other group cannot turn on, with a small Contact sales button', () => {
      expect(findRow('bank').text()).toContain('Contact sales to get GitLab Orbit for this group');
      expect(findRowSales('bank').props()).toMatchObject({
        glmContent: 'orbit-off-page',
        size: 'small',
        namespaceId: 7,
      });
    });

    it('highlights only the selected row', () => {
      expect(findRow('acme').classes()).toContain('gl-bg-feedback-info');
      expect(findRow('bank').classes()).not.toContain('gl-bg-feedback-info');
    });
  });

  describe.each`
    action               | statusText
    ${'not_licensed'}    | ${'GitLab Orbit is available on Premium and Ultimate'}
    ${'not_available'}   | ${'Contact sales to get GitLab Orbit for this group'}
    ${'trial_ended'}     | ${'Trial ended'}
    ${'credits_used_up'} | ${'Credits used up'}
  `('with a group that has $action', ({ action, statusText }) => {
    beforeEach(() => createComponent({ rows: [buildRow({ action })] }));

    it('shows the status and Contact sales, and no selection column', () => {
      expect(findRow('acme').text()).toContain(statusText);
      expect(findRowSales('acme').exists()).toBe(true);
      expect(findSelectAll().exists()).toBe(false);
    });
  });

  describe('on GitLab Self-Managed', () => {
    describe.each`
      action               | text
      ${'not_licensed'}    | ${'Ask your administrator'}
      ${'not_available'}   | ${'Ask your administrator'}
      ${'not_eligible'}    | ${'Ask your administrator'}
      ${'trial_ended'}     | ${'Trial ended'}
      ${'credits_used_up'} | ${'Trial ended'}
    `('with a group that has $action', ({ action, text }) => {
      beforeEach(() => createComponent({ saas: false, rows: [buildRow({ action })] }));

      it('shows the instance availability and no Contact sales in the row', () => {
        expect(findRowAvailability('acme').text()).toBe(text);
        expect(findRowSales('acme').exists()).toBe(false);
      });

      it('shows no GitLab.com plan copy', () => {
        expect(findRow('acme').text()).not.toContain('Premium and Ultimate');
      });
    });

    describe('with a group during the instance trial', () => {
      beforeEach(() =>
        createComponent({
          saas: false,
          rows: [buildRow({ action: 'turn_on', trialActive: true })],
        }),
      );

      it('says that the trial is for the instance', () => {
        expect(findRowAvailability('acme').text()).toBe('Trial active');
      });
    });
  });

  describe.each`
    description                       | row                                                   | text
    ${'starts a trial with no offer'} | ${buildRow()}                                         | ${'Trial when turned on'}
    ${'has an active trial'}          | ${buildRow({ action: 'turn_on', trialActive: true })} | ${'Trial active'}
    ${'has no trial details'}         | ${buildRow({ action: 'unavailable' })}                | ${'Could not load'}
  `('with a group that $description', ({ row, text }) => {
    beforeEach(() => createComponent({ rows: [row] }));

    it('shows the availability text', () => {
      expect(findRowAvailability('acme').text()).toBe(text);
    });
  });

  describe('with only groups that turn on outside a trial', () => {
    beforeEach(() =>
      createComponent({
        rows: [
          buildRow({ key: 'acme', action: 'turn_on' }),
          buildRow({ key: 'data', action: 'turn_on' }),
        ],
      }),
    );

    it('shows no Availability column', () => {
      expect(wrapper.find('thead').text()).not.toContain('Availability');
      expect(findRowAvailability('acme').exists()).toBe(false);
    });
  });

  describe('with a group outside a trial and a group with an active trial', () => {
    beforeEach(() =>
      createComponent({
        rows: [
          buildRow({ key: 'acme', action: 'turn_on' }),
          buildRow({
            key: 'data',
            action: 'turn_on',
            trialActive: true,
          }),
        ],
      }),
    );

    it('shows the Availability column, empty for the group outside a trial', () => {
      expect(wrapper.find('thead').text()).toContain('Availability');
      expect(findRowAvailability('acme').text()).toBe('');
      expect(findRowAvailability('data').text()).toBe('Trial active');
    });
  });

  describe('selection', () => {
    const rows = [buildRow({ key: 'acme' }), buildRow({ key: 'data', action: 'turn_on' })];

    describe('when the user checks a group', () => {
      beforeEach(async () => {
        createComponent({ rows, selected: ['acme'] });
        await findRowCheckbox('data').setChecked(true);
      });

      it('emits the selection with that group added', () => {
        expect(wrapper.emitted('update:selected')).toEqual([[['acme', 'data']]]);
      });
    });

    describe('when the user unchecks a group', () => {
      beforeEach(async () => {
        createComponent({ rows, selected: ['acme', 'data'] });
        await findRowCheckbox('acme').setChecked(false);
      });

      it('emits the selection with that group removed', () => {
        expect(wrapper.emitted('update:selected')).toEqual([[['data']]]);
      });
    });

    describe('when some groups are selected', () => {
      beforeEach(() => createComponent({ rows, selected: ['acme'] }));

      it('shows the header checkbox as indeterminate', () => {
        expect(findSelectAllInput().element.indeterminate).toBe(true);
      });

      describe('and the user checks the header checkbox', () => {
        beforeEach(() => findSelectAllInput().setChecked(true));

        it('selects every group that can turn on', () => {
          expect(wrapper.emitted('update:selected')).toEqual([[['acme', 'data']]]);
        });
      });
    });

    describe('when every group is selected and the user unchecks the header checkbox', () => {
      beforeEach(async () => {
        createComponent({ rows, selected: ['acme', 'data'] });
        await findSelectAllInput().setChecked(false);
      });

      it('clears the selection', () => {
        expect(wrapper.emitted('update:selected')).toEqual([[[]]]);
      });
    });
  });
});
