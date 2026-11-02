import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DropdownFooter from '~/sidebar/components/labels/labels_select_widget/dropdown_footer.vue';

describe('DropdownFooter', () => {
  let wrapper;

  const createComponent = ({ props = {}, injected = {} } = {}) => {
    wrapper = shallowMountExtended(DropdownFooter, {
      propsData: {
        footerCreateLabelTitle: 'create',
        footerManageLabelTitle: 'manage',
        ...props,
      },
      provide: {
        allowLabelCreate: true,
        labelsManagePath: 'foo/bar',
        ...injected,
      },
    });
  };

  const findCreateLabelButton = () => wrapper.findComponentByTestId('create-label-button');
  const findManageLabelsButton = () => wrapper.findComponentByTestId('manage-labels-button');

  describe('Labels view', () => {
    beforeEach(() => {
      createComponent();
    });

    it('does not render create label button if `allowLabelCreate` is false', () => {
      createComponent({ injected: { allowLabelCreate: false } });

      expect(findCreateLabelButton().exists()).toBe(false);
    });

    describe('when `allowLabelCreate` is true', () => {
      beforeEach(() => {
        createComponent();
      });

      it('renders create label button', () => {
        expect(findCreateLabelButton().exists()).toBe(true);
      });

      it('emits `toggle-dropdown-contents-create-view` event on create label button click', () => {
        const event = new MouseEvent('click');
        jest.spyOn(event, 'stopPropagation');
        findCreateLabelButton().vm.$emit('click', event);

        expect(wrapper.emitted('toggle-dropdown-contents-create-view')).toEqual([[]]);
        expect(event.stopPropagation).toHaveBeenCalled();
      });
    });

    describe('manage labels button', () => {
      it('is rendered', () => {
        expect(findManageLabelsButton().exists()).toBe(true);
      });

      it('stops the click from propagating', () => {
        const event = new MouseEvent('click');
        jest.spyOn(event, 'stopPropagation');
        findManageLabelsButton().vm.$emit('click', event);

        expect(event.stopPropagation).toHaveBeenCalled();
      });

      describe('when footerManageLabelTitle is not given', () => {
        beforeEach(() => {
          createComponent({ props: { footerManageLabelTitle: undefined } });
        });

        it('does not render manage labels button', () => {
          expect(findManageLabelsButton().exists()).toBe(false);
        });
      });

      describe('when labelsManagePath is not provided', () => {
        beforeEach(() => {
          createComponent({ injected: { labelsManagePath: '' } });
        });

        it('does not render manage labels button', () => {
          expect(findManageLabelsButton().exists()).toBe(false);
        });
      });
    });
  });
});
