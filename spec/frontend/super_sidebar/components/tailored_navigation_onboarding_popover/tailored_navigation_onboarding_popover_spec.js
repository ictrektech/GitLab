import { GlFormRadioGroup, GlPopover } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import TailoredNavigationOnboardingPopover from '~/super_sidebar/components/tailored_navigation_onboarding_popover/tailored_navigation_onboarding_popover.vue';

describe('TailoredNavigationOnboardingPopover', () => {
  let wrapper;

  const createComponent = ({ props = {}, panelType = 'project', attachTo } = {}) => {
    wrapper = mountExtended(TailoredNavigationOnboardingPopover, {
      attachTo,
      provide: { panelType },
      propsData: {
        navMode: 'compact',
        ...props,
      },
      stubs: { GlPopover: stubComponent(GlPopover, { template: '<div><slot></slot></div>' }) },
    });
  };

  const findPopover = () => wrapper.findComponent(GlPopover);
  const findStepLabel = () => wrapper.findByTestId('onboarding-step-label');
  const findNext = () => wrapper.findByTestId('onboarding-next');
  const findBack = () => wrapper.findByTestId('onboarding-back');
  const findDone = () => wrapper.findByTestId('onboarding-done');
  const findBody = () => wrapper.find('p');
  const findNavModeRadios = () =>
    wrapper.findByTestId('onboarding-nav-mode').findAll('input[type="radio"]');
  const findNavModeLabels = () =>
    wrapper
      .findByTestId('onboarding-nav-mode')
      .findAll('label')
      .wrappers.map((label) => label.text());
  const findCheckedStates = () =>
    findNavModeRadios().wrappers.map((radio) => radio.element.checked);

  describe('popover', () => {
    it('anchors the first step to the sidebar preferences toggle', () => {
      createComponent();

      expect(findPopover().props()).toMatchObject({
        target: 'super-sidebar-preferences-toggle',
        title: 'Tailor your sidebar experience',
      });
    });

    // The sidebar's scroll area is too narrow for placement="right", so the default
    // scrollParent boundary would flip the popover over the sidebar.
    it('is bounded by the viewport', () => {
      createComponent();

      expect(findPopover().props('boundary')).toBe('viewport');
    });

    it('emits close when the close button is clicked', () => {
      createComponent();

      findPopover().vm.$emit('close-button-clicked');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    describe('when not visible', () => {
      beforeEach(() => {
        createComponent({ props: { visible: false } });
      });

      it('does not render the popover', () => {
        expect(findPopover().exists()).toBe(false);
      });
    });

    describe('when hidden and shown again', () => {
      beforeEach(async () => {
        createComponent();
        await findNext().trigger('click');
        await wrapper.setProps({ visible: false });
        await wrapper.setProps({ visible: true });
      });

      it('keeps the current step', () => {
        expect(findStepLabel().text()).toBe('Step 2 of 2');
      });
    });
  });

  describe('keyboard and focus', () => {
    // Mirrors the real popover element, which BootstrapVue makes focusable with tabindex="-1".
    const showPopover = (element = wrapper.element) => {
      element.setAttribute('tabindex', '-1');
      findPopover().vm.$emit('shown', { relatedTarget: element });
    };
    const pressKey = (key, element = wrapper.element) =>
      element.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true }));

    beforeEach(() => {
      createComponent({ attachTo: document.body });
    });

    describe('when the popover is shown', () => {
      it('moves focus to the popover', () => {
        showPopover();

        expect(document.activeElement).toBe(wrapper.element);
      });

      describe('while focus is on the autofocused top bar landmark', () => {
        let header;

        beforeEach(() => {
          header = document.createElement('header');
          header.tabIndex = 0;
          header.setAttribute('autofocus', '');
          document.body.appendChild(header);
          header.focus();
          showPopover();
        });

        afterEach(() => {
          header.remove();
        });

        it('moves focus into the popover', () => {
          expect(document.activeElement).toBe(wrapper.element);
        });
      });

      describe.each`
        tag        | autofocus | description
        ${'input'} | ${false}  | ${'typing in a field'}
        ${'input'} | ${true}   | ${'typing in an autofocused field'}
        ${'a'}     | ${false}  | ${'on a link the user tabbed to'}
      `('while focus is $description', ({ tag, autofocus }) => {
        let element;

        beforeEach(() => {
          element = document.createElement(tag);
          if (autofocus) element.setAttribute('autofocus', '');
          element.tabIndex = 0;
          document.body.appendChild(element);
          element.focus();
          showPopover();
        });

        afterEach(() => {
          element.remove();
        });

        it('leaves focus where it is', () => {
          expect(document.activeElement).toBe(element);
        });

        it('still moves focus into the popover when the user goes to the next step', async () => {
          await findNext().trigger('click');
          showPopover();

          expect(document.activeElement).toBe(wrapper.element);
        });
      });
    });

    describe('when the popover is hidden and shown again on the same step', () => {
      let otherElement;

      beforeEach(async () => {
        showPopover();
        otherElement = document.createElement('button');
        document.body.appendChild(otherElement);
        otherElement.focus();

        await wrapper.setProps({ visible: false });
        await wrapper.setProps({ visible: true });
        showPopover();
      });

      afterEach(() => {
        otherElement.remove();
      });

      it('leaves focus where it is', () => {
        expect(document.activeElement).toBe(otherElement);
      });
    });

    describe('when a key is pressed inside the popover', () => {
      beforeEach(() => {
        showPopover();
      });

      it('emits close for Escape', () => {
        pressKey('Escape');

        expect(wrapper.emitted('close')).toHaveLength(1);
      });

      it('ignores other keys', () => {
        pressKey('Enter');

        expect(wrapper.emitted('close')).toBeUndefined();
      });

      describe('after the component is destroyed', () => {
        it('no longer emits close for Escape', () => {
          const { element } = wrapper;
          wrapper.destroy();

          pressKey('Escape', element);

          expect(wrapper.emitted('close')).toBeUndefined();
        });
      });
    });

    describe('when the popover is shown again for the next step', () => {
      let previousElement;
      let nextElement;

      beforeEach(async () => {
        previousElement = document.createElement('div');
        nextElement = document.createElement('div');
        document.body.append(previousElement, nextElement);

        showPopover(previousElement);
        await findNext().trigger('click');
        showPopover(nextElement);
      });

      afterEach(() => {
        previousElement.remove();
        nextElement.remove();
      });

      it('focuses the new popover', () => {
        expect(document.activeElement).toBe(nextElement);
      });

      it('only listens for Escape on the new popover', () => {
        pressKey('Escape', previousElement);

        expect(wrapper.emitted('close')).toBeUndefined();

        pressKey('Escape', nextElement);

        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    describe('when the popover closes', () => {
      let anchors;

      beforeEach(() => {
        anchors = ['super-sidebar-preferences-toggle', 'super-sidebar-feature-library-trigger'].map(
          (id) => {
            const anchor = document.createElement('button');
            anchor.id = id;
            document.body.appendChild(anchor);
            return anchor;
          },
        );
        showPopover();
      });

      afterEach(() => {
        anchors.forEach((anchor) => anchor.remove());
      });

      it.each`
        description                | close
        ${'with Escape'}           | ${() => pressKey('Escape')}
        ${'with the close button'} | ${() => findPopover().vm.$emit('close-button-clicked')}
      `('returns focus to the step anchor $description', ({ close }) => {
        close();

        expect(document.activeElement).toBe(anchors[0]);
        expect(wrapper.emitted('close')).toHaveLength(1);
      });

      it('returns focus to the Feature catalog item when Done is clicked', async () => {
        await findNext().trigger('click');
        await findDone().trigger('click');

        expect(document.activeElement).toBe(anchors[1]);
        expect(wrapper.emitted('close')).toHaveLength(1);
      });
    });

    it('announces step changes politely', () => {
      expect(findStepLabel().attributes('aria-live')).toBe('polite');
    });
  });

  describe('step navigation', () => {
    beforeEach(() => {
      createComponent();
    });

    it('starts on the first step with only a Next button', () => {
      expect(findStepLabel().text()).toBe('Step 1 of 2');
      expect(findBack().exists()).toBe(false);
      expect(findNext().exists()).toBe(true);
      expect(findDone().exists()).toBe(false);
    });

    it('moves forward and back between steps, reporting the catalog step', async () => {
      await findNext().trigger('click');

      expect(findStepLabel().text()).toBe('Step 2 of 2');
      expect(wrapper.emitted('catalog-step')).toEqual([[true]]);

      await findBack().trigger('click');

      expect(findStepLabel().text()).toBe('Step 1 of 2');
      expect(wrapper.emitted('catalog-step')).toEqual([[true], [false]]);
    });
  });

  describe('layout step', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    beforeEach(() => {
      createComponent({ panelType: 'group' });
    });

    it('introduces pins', () => {
      expect(findBody().text()).toBe(
        'Your sidebar is built around your pins. Choose how much of the sidebar to show.',
      );
    });

    it('renders the two layouts as radios in a labelled fieldset, with the current one checked', () => {
      expect(findNavModeLabels()).toEqual(['Compact', 'Full']);
      expect(findCheckedStates()).toEqual([true, false]);
      expect(wrapper.find('fieldset legend').text()).toBe('Layout');
    });

    describe('when another layout is picked', () => {
      let trackEventSpy;

      beforeEach(async () => {
        ({ trackEventSpy } = bindInternalEventDocument(wrapper.element));
        await findNavModeRadios().at(1).setChecked();
      });

      it('emits nav-mode-change and tracks the choice', () => {
        expect(wrapper.emitted('nav-mode-change')).toEqual([['all_categories']]);
        expect(trackEventSpy).toHaveBeenCalledWith(
          'select_sidebar_navigation_mode_in_sidebar_preferences',
          { label: 'group', property: 'all_categories' },
          undefined,
        );
      });
    });

    describe('when the layout changes while the popover is open', () => {
      beforeEach(async () => {
        await wrapper.setProps({ navMode: 'all_categories' });
      });

      it('checks the new layout', () => {
        expect(findCheckedStates()).toEqual([false, true]);
      });
    });

    describe('when the current layout is picked again', () => {
      it('does not emit or track', async () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        await wrapper.findComponent(GlFormRadioGroup).vm.$emit('change', 'compact');

        expect(wrapper.emitted('nav-mode-change')).toBeUndefined();
        expect(trackEventSpy).not.toHaveBeenCalled();
      });
    });
  });

  describe('feature catalog step', () => {
    beforeEach(async () => {
      createComponent();
      await findNext().trigger('click');
    });

    it('anchors to the feature catalog item and points the user at it', () => {
      expect(findPopover().props('target')).toBe('super-sidebar-feature-library-trigger');
      expect(findBody().text()).toBe(
        'Explore and pin more features at any time from the Feature catalog.',
      );
    });

    it('replaces Next with Done', () => {
      expect(findNext().exists()).toBe(false);
      expect(findDone().exists()).toBe(true);
    });

    it('emits close when Done is clicked', async () => {
      await findDone().trigger('click');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });
});
