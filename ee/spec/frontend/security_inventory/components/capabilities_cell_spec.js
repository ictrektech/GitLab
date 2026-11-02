import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CapabilitiesCell from 'ee/security_inventory/components/capabilities_cell.vue';

describe('CapabilitiesCell', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(CapabilitiesCell);
  };

  beforeEach(() => {
    createComponent();
  });

  it('renders a placeholder until capability data is shown', () => {
    expect(wrapper.findByTestId('capabilities-cell-placeholder').text()).toBe('—');
  });
});
