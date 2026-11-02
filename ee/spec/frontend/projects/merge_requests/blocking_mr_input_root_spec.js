import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import BlockingMrInputRoot from 'ee/projects/merge_requests/blocking_mr_input_root.vue';
import RelatedIssuableInput from '~/related_issues/components/related_issuable_input.vue';

describe('blocking mr input root', () => {
  let wrapper;

  const getInput = () => wrapper.findComponent(RelatedIssuableInput);
  const addTokenizedInput = (input) => {
    getInput().vm.$emit('add-issuable-form-input', {
      untouchedRawReferences: [input],
      touchedReference: '',
    });
  };
  const addInput = (input) => {
    getInput().vm.$emit('add-issuable-form-input', {
      untouchedRawReferences: [],
      touchedReference: input,
    });
  };
  const removeRef = (index) => {
    getInput().vm.$emit('pending-issuable-remove-request', index);
  };
  const createComponent = (propsData = {}) => {
    wrapper = shallowMount(BlockingMrInputRoot, { propsData });
  };

  it('does not keep duplicate references', () => {
    createComponent();
    const input = '!1';

    addTokenizedInput(input);
    addTokenizedInput(input);

    expect(wrapper.vm.references).toEqual(['!1']);
  });

  it('updates input value to empty string when adding a tokenized input', () => {
    createComponent();

    addTokenizedInput('foo');

    expect(wrapper.vm.inputValue).toBe('');
  });

  it('updates input value to ref when typing into input (before adding whitespace)', () => {
    createComponent();

    addInput('foo');

    expect(wrapper.vm.inputValue).toBe('foo');
  });

  it('does not reorder when adding a ref that already exists', () => {
    const input = '!1';
    createComponent({
      existingRefs: [input, '!2'],
    });

    addTokenizedInput(input, wrapper);

    expect(wrapper.vm.references).toEqual(['!1', '!2']);
  });

  describe('blur', () => {
    it.each(['', '   '])('does not add a reference for the value "%s"', async (value) => {
      createComponent();

      getInput().vm.$emit('add-issuable-form-blur', value);
      await nextTick();

      expect(getInput().props('references')).toEqual([]);
    });

    it('adds the trimmed value as a reference', async () => {
      createComponent();

      getInput().vm.$emit('add-issuable-form-blur', ' !1 ');
      await nextTick();

      expect(getInput().props('references')).toEqual(['!1']);
    });
  });

  describe('"finish" keystrokes (Enter or Tab)', () => {
    const createEvent = (overrides = {}) => ({
      key: 'Enter',
      ctrlKey: false,
      metaKey: false,
      shiftKey: false,
      preventDefault: jest.fn(),
      stopPropagation: jest.fn(),
      ...overrides,
    });
    const finishEntry = (value, event) => {
      getInput().vm.$emit('add-issuable-finish-entry', { value, event });
      return nextTick();
    };
    const expectEventCaptured = (event) => {
      expect(event.preventDefault).toHaveBeenCalledTimes(1);
      expect(event.stopPropagation).toHaveBeenCalledTimes(1);
    };
    const expectEventPassedThrough = (event) => {
      expect(event.preventDefault).not.toHaveBeenCalled();
      expect(event.stopPropagation).not.toHaveBeenCalled();
    };

    beforeEach(() => {
      createComponent();
    });

    describe.each`
      keystroke      | eventOverrides
      ${'Tab'}       | ${{ key: 'Tab' }}
      ${'Shift+Tab'} | ${{ key: 'Tab', shiftKey: true }}
    `('$keystroke', ({ eventOverrides }) => {
      describe.each(['', '   '])('when the input value is "%s"', (value) => {
        let event;

        beforeEach(async () => {
          event = createEvent(eventOverrides);
          await finishEntry(value, event);
        });

        it('lets focus leave the field', () => {
          expectEventPassedThrough(event);
        });

        it('does not add a reference', () => {
          expect(getInput().props('references')).toEqual([]);
        });
      });

      describe('when the input has a value', () => {
        let event;

        beforeEach(async () => {
          event = createEvent(eventOverrides);
          await finishEntry('!1', event);
        });

        it('keeps focus in the field', () => {
          expectEventCaptured(event);
        });

        it('adds the value as a reference and clears the input', () => {
          expect(getInput().props('references')).toEqual(['!1']);
          expect(getInput().props('inputValue')).toBe('');
        });

        it('lets focus leave the field on the next press', async () => {
          const nextEvent = createEvent(eventOverrides);
          await finishEntry('', nextEvent);

          expectEventPassedThrough(nextEvent);
          expect(getInput().props('references')).toEqual(['!1']);
        });
      });
    });

    describe('Enter', () => {
      it.each(['', '   '])(
        'does not submit the form or add a reference for the value "%s"',
        async (value) => {
          const event = createEvent();
          await finishEntry(value, event);

          expectEventCaptured(event);
          expect(getInput().props('references')).toEqual([]);
        },
      );

      it('adds each value as a reference without submitting the form', async () => {
        const firstEvent = createEvent();
        const secondEvent = createEvent();
        await finishEntry('!1', firstEvent);
        await finishEntry('!2', secondEvent);

        expectEventCaptured(firstEvent);
        expectEventCaptured(secondEvent);
        expect(getInput().props('references')).toEqual(['!1', '!2']);
      });
    });

    describe('with modifiers', () => {
      it.each`
        modifier  | eventOverrides
        ${'Cmd'}  | ${{ metaKey: true, key: 'Tab' }}
        ${'Ctrl'} | ${{ ctrlKey: true, key: 'Tab' }}
      `('$modifier does not affect the Tab handler', async ({ eventOverrides }) => {
        const event = createEvent(eventOverrides);
        await finishEntry('!1', event);

        expectEventCaptured(event);
        expect(getInput().props('references')).toEqual(['!1']);
      });

      describe.each`
        modifier  | eventOverrides
        ${'Cmd'}  | ${{ metaKey: true }}
        ${'Ctrl'} | ${{ ctrlKey: true }}
      `('$modifier+Enter', ({ eventOverrides }) => {
        it.each(['', '!1'])(
          'passes through to submit the form for the value "%s"',
          async (value) => {
            const event = createEvent(eventOverrides);
            await finishEntry(value, event);

            expectEventPassedThrough(event);
            expect(getInput().props('references')).toEqual([]);
          },
        );
      });
    });
  });
  describe('hidden inputs', () => {
    const createHiddenInputExpectation = (selector) => (expected) => {
      expect(wrapper.find(selector).element.value).toBe(expected);
    };

    describe('update_blocking_merge_request_refs', () => {
      const expectShouldUpdateRefsToBe = createHiddenInputExpectation(
        'input[name="merge_request[update_blocking_merge_request_refs]"]',
      );

      it('is false when nothing happens', () => {
        createComponent();

        expectShouldUpdateRefsToBe('false');
      });

      it('is true after a ref is removed', async () => {
        createComponent({ existingRefs: ['!1'] });
        removeRef(0);

        await nextTick();
        expectShouldUpdateRefsToBe('true');
      });

      it('is true after a ref is added', async () => {
        createComponent();
        addTokenizedInput('foo');

        await nextTick();
        expectShouldUpdateRefsToBe('true');
      });
    });

    describe('remove_hidden_blocking_merge_requests', () => {
      const expectRemoveHiddenBlockingMergeRequestsToBe = createHiddenInputExpectation(
        'input[name="merge_request[remove_hidden_blocking_merge_requests]"]',
      );
      const makeComponentWithHiddenMrs = () => {
        const hiddenMrsRef = { text: '2 inaccessible merge requests', isHiddenRef: true };
        createComponent({
          containsHiddenBlockingMrs: true,
          existingRefs: ['!1', '!2', hiddenMrsRef],
        });
      };

      it('is false when nothing has happened', () => {
        makeComponentWithHiddenMrs();

        expectRemoveHiddenBlockingMergeRequestsToBe('false');
      });

      it('does not render a reference input for the hidden refs placeholder', () => {
        makeComponentWithHiddenMrs();

        const values = wrapper
          .findAll('input[name="merge_request[blocking_merge_request_references][]"]')
          .wrappers.map((input) => input.element.value);

        expect(values).toEqual(['!1', '!2']);
      });

      it('is false when removing a visible ref', async () => {
        makeComponentWithHiddenMrs();
        removeRef(0);

        await nextTick();
        expectRemoveHiddenBlockingMergeRequestsToBe('false');
      });

      it('is true when the hidden refs placeholder is removed', async () => {
        makeComponentWithHiddenMrs();
        removeRef(2);

        await nextTick();
        expectRemoveHiddenBlockingMergeRequestsToBe('true');
      });
    });
  });
});
