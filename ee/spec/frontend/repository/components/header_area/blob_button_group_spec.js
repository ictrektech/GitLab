import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import BlobButtonGroup from 'ee/repository/components/header_area/blob_button_group.vue';
import CeBlobButtonGroup from '~/repository/components/header_area/blob_button_group.vue';

describe('EE BlobButtonGroup', () => {
  let wrapper;

  const propsData = {
    currentRef: 'main',
    isUsingLfs: false,
    userPermissions: { pushCode: true, createMergeRequestIn: true },
    isReplaceDisabled: false,
    projectPath: 'some/project',
    canCreateLock: true,
    canDestroyLock: false,
    isLocked: false,
  };

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(BlobButtonGroup, { propsData: { ...propsData, ...props } });
  };

  const findCeBlobButtonGroup = () => wrapper.findComponent(CeBlobButtonGroup);

  it('forwards its props to the CE component', () => {
    createComponent();

    expect(findCeBlobButtonGroup().props()).toMatchObject({
      currentRef: 'main',
      isUsingLfs: false,
      isReplaceDisabled: false,
    });
  });

  it('declares the EE-only lock props on top of the CE props', () => {
    expect(Object.keys(BlobButtonGroup.props)).toEqual(
      expect.arrayContaining([
        ...Object.keys(CeBlobButtonGroup.props),
        'projectPath',
        'canCreateLock',
        'canDestroyLock',
        'isLocked',
        'isLoading',
      ]),
    );
  });

  it('re-emits show-fork-suggestion', () => {
    createComponent();

    findCeBlobButtonGroup().vm.$emit('show-fork-suggestion');

    expect(wrapper.emitted('show-fork-suggestion')).toHaveLength(1);
  });
});
