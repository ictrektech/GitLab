import { GlDisclosureDropdownGroup } from '@gitlab/ui';
import BlobRepositoryActionsGroup from '~/repository/components/header_area/blob_repository_actions_group.vue';
import PermalinkDropdownItem from '~/repository/components/header_area/permalink_dropdown_item.vue';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import Shortcuts from '~/behaviors/shortcuts/shortcuts';
import { keysFor, START_SEARCH_PROJECT_FILE } from '~/behaviors/shortcuts/keybindings';
import { keyboardShortcutsDisabled } from '~/behaviors/shortcuts/shortcuts_disabled';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import { blobControlsDataMock } from 'ee_else_ce_jest/repository/mock_data';

jest.mock('~/behaviors/shortcuts/shortcuts_disabled');

const relativePermalinkPath =
  'flightjs/Flight/-/blob/46ca9ebd5a43ec240ee8d64e2bb829169dff744e/bower.json';

describe('BlobRepositoryActionsGroup', () => {
  let wrapper;
  let mockRouterPush;

  const createComponent = ({ props = {}, provided = {}, route = { query: {}, hash: '' } } = {}) => {
    mockRouterPush = jest.fn();
    wrapper = shallowMountExtended(BlobRepositoryActionsGroup, {
      propsData: {
        permalinkPath: relativePermalinkPath,
        ...props,
      },
      provide: {
        blobInfo: blobControlsDataMock.repository.blobs.nodes[0],
        ...provided,
      },
      stubs: {
        GlDisclosureDropdownGroup,
        PermalinkDropdownItem,
      },
      mocks: {
        $route: route,
        $router: { push: mockRouterPush },
      },
    });
  };

  const findDropdownGroup = () => wrapper.findComponent(GlDisclosureDropdownGroup);
  const findFindFileDropdownItem = () => wrapper.findComponentByTestId('find');
  const findBlameDropdownItem = () => wrapper.findComponentByTestId('blame-dropdown-item');
  const findPermalinkLinkDropdown = () => wrapper.findComponent(PermalinkDropdownItem);
  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  beforeEach(() => {
    createComponent();
  });

  it('renders correctly', () => {
    expect(findDropdownGroup().exists()).toBe(true);
    expect(findFindFileDropdownItem().exists()).toBe(true);
    expect(findBlameDropdownItem().props()).toStrictEqual({
      disabled: false,
      icon: null,
      item: {
        extraAttrs: {
          'data-testid': 'blame',
        },
        text: 'Blame',
      },
      siblingsHaveIcons: false,
      variant: null,
    });
    expect(findPermalinkLinkDropdown().props()).toStrictEqual({
      permalinkPath: 'flightjs/Flight/-/blob/46ca9ebd5a43ec240ee8d64e2bb829169dff744e/bower.json',
      source: 'blob',
    });
  });

  describe('Find file dropdown item', () => {
    it('is hidden at the same breakpoint the header Find file button appears', () => {
      expect(findFindFileDropdownItem().classes()).toContain('@md/panel:gl-hidden');
    });

    it('triggers a `focusSearchFile` shortcut when the findFile button is clicked', () => {
      jest.spyOn(Shortcuts, 'focusSearchFile').mockResolvedValue();
      findFindFileDropdownItem().vm.$emit('action');

      expect(Shortcuts.focusSearchFile).toHaveBeenCalled();
    });

    it('emits a tracking event when the Find file button is clicked', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
      jest.spyOn(Shortcuts, 'focusSearchFile').mockResolvedValue();

      findFindFileDropdownItem().vm.$emit('action');

      expect(trackEventSpy).toHaveBeenCalledWith('click_find_file_button_on_repository_pages');
    });
  });

  describe('Blame dropdown item', () => {
    it('renders only on mobile layout', () => {
      expect(findBlameDropdownItem().classes()).toContain('@sm/panel:gl-hidden');
    });

    it('does not render for lfs files', () => {
      createComponent({
        provided: {
          blobInfo: {
            ...blobControlsDataMock.repository.blobs.nodes[0],
            storedExternally: true,
            externalStorage: 'lfs',
          },
        },
      });

      expect(findBlameDropdownItem().exists()).toBe(false);
    });

    it('does not render for binary files', () => {
      createComponent({ props: { isBinaryFileType: true } });

      expect(findBlameDropdownItem().exists()).toBe(false);
    });

    describe('when clicked', () => {
      beforeEach(() => {
        // Line highlighting updates the URL hash without going through the router
        setWindowLocation('#L42');
        createComponent({ route: { query: { plain: '1' }, hash: '' } });
        findBlameDropdownItem().vm.$emit('action');
      });

      it('adds the blame param to the current route, keeping the query and line hash', () => {
        expect(mockRouterPush).toHaveBeenCalledWith({
          query: { plain: '1', blame: '1' },
          hash: '#L42',
        });
      });
    });

    it('does not render while blame is shown', () => {
      createComponent({ route: { query: { blame: '1' }, hash: '' } });

      expect(findBlameDropdownItem().exists()).toBe(false);
    });
  });

  it('displays the shortcut key when shortcuts are not disabled', () => {
    keyboardShortcutsDisabled.mockReturnValue(false);
    createComponent();
    expect(findFindFileDropdownItem().find('kbd').exists()).toBe(true);
    expect(findFindFileDropdownItem().find('kbd').text()).toBe(
      keysFor(START_SEARCH_PROJECT_FILE)[0],
    );
  });

  it('does not display the shortcut key when shortcuts are disabled', () => {
    keyboardShortcutsDisabled.mockReturnValue(true);
    createComponent();
    expect(findFindFileDropdownItem().find('kbd').exists()).toBe(false);
  });
});
