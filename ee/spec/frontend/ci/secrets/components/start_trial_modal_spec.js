import { GlModal, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import StartTrialModal from 'ee/ci/secrets/components/start_trial_modal.vue';

describe('StartTrialModal', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(StartTrialModal, {
      propsData: {
        visible: true,
        scope: 'instance',
        ...props,
      },
      stubs: { GlModal, GlSprintf },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);

  beforeEach(() => {
    createComponent();
  });

  it('passes visible prop to GlModal', () => {
    expect(findModal().props('visible')).toBe(true);
  });

  it('emits `start-trial` when the primary action fires', () => {
    findModal().vm.$emit('primary');

    expect(wrapper.emitted('start-trial')).toHaveLength(1);
  });

  it('emits `hide` when the modal is hidden', () => {
    findModal().vm.$emit('hidden');

    expect(wrapper.emitted('hide')).toHaveLength(1);
  });

  it.each`
    scope         | text
    ${'instance'} | ${'across all projects and subgroups in your instance.'}
    ${'group'}    | ${'across all projects and subgroups in your group.'}
  `('describes the trial credits for the $scope scope', ({ scope, text }) => {
    createComponent({ scope });

    expect(findModal().text()).toContain(text);
  });
});
