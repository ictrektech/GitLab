import { GlBadge, GlFormRadio, GlFormRadioGroup } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EnableScannersSelectMode from 'ee/security_configuration/components/enable_scanners_wizard/select_mode.vue';

describe('EnableScannersSelectMode', () => {
  let wrapper;
  let enableScanners;

  const createComponent = ({ attachMode = 'FILL_SCAN_GAPS' } = {}) => {
    enableScanners = { attachMode };
    wrapper = shallowMountExtended(EnableScannersSelectMode, {
      provide: { enableScanners },
    });
  };

  const findRadioGroup = () => wrapper.findComponent(GlFormRadioGroup);
  const findRadios = () => wrapper.findAllComponents(GlFormRadio);

  beforeEach(() => {
    createComponent();
  });

  it('renders the modes in order', () => {
    expect(findRadios().wrappers.map((radio) => radio.attributes('value'))).toEqual([
      'SET',
      'FILL_SCAN_GAPS',
      'REPLACE',
    ]);
    expect(findRadios().at(0).text()).toContain('All projects');
    expect(findRadios().at(1).text()).toContain("Projects that don't scan yet");
    expect(findRadios().at(2).text()).toContain('Replace existing');
  });

  it('shows the Recommended badge on one mode', () => {
    expect(findRadios().at(1).findComponent(GlBadge).text()).toBe('Recommended');
    expect(wrapper.findAllComponents(GlBadge)).toHaveLength(1);
  });

  it('sets the radio group to the current attach mode', () => {
    expect(findRadioGroup().attributes('checked')).toBe('FILL_SCAN_GAPS');
  });

  it.each(['SET', 'FILL_SCAN_GAPS', 'REPLACE'])(
    'sets the attach mode to %s on select',
    (attachMode) => {
      createComponent({ attachMode: null });

      findRadioGroup().vm.$emit('input', attachMode);

      expect(enableScanners.attachMode).toBe(attachMode);
    },
  );
});
