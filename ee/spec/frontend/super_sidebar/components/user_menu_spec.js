import { GlDisclosureDropdown } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import UserMenu from '~/super_sidebar/components/user_menu.vue';
import UserMenuUpgradeSubscription from 'ee_component/super_sidebar/components/user_menu_upgrade_subscription.vue';
import UserMenuExplorePremium from 'ee_component/super_sidebar/components/user_menu_explore_premium.vue';
import { userMenuMockData } from '../mock_data';

describe('UserMenu component', () => {
  let wrapper;
  const findUserMenuUpgradeSubscription = () => wrapper.findComponent(UserMenuUpgradeSubscription);
  const findUserMenuExplorePremium = () => wrapper.findComponent(UserMenuExplorePremium);
  const showDropdown = () => wrapper.findComponent(GlDisclosureDropdown).vm.$emit('shown');

  const createWrapper = (userDataChanges = {}, stubs = {}) => {
    wrapper = shallowMountExtended(UserMenu, {
      propsData: {
        data: {
          ...userMenuMockData,
          ...userDataChanges,
        },
      },
      stubs: {
        ...stubs,
      },
      provide: {
        isImpersonating: false,
        isSaas: false,
      },
    });
  };

  describe('Upgrade subscription component', () => {
    describe('when upgrade_link is not provided', () => {
      it('should not render the upgrade subscription component', () => {
        createWrapper();
        expect(findUserMenuUpgradeSubscription().exists()).toBe(false);
      });
    });

    describe('when upgrade_link is provided', () => {
      const upgradeLink = {
        url: '/groups/test-group/-/billings',
        text: 'Upgrade subscription',
      };

      it('renders the upgrade subscription component with the upgrade_link prop', () => {
        createWrapper({ upgrade_link: upgradeLink });
        expect(findUserMenuUpgradeSubscription().props('upgradeLink')).toEqual(upgradeLink);
      });
    });
  });

  describe('Explore Premium component', () => {
    describe('when explore_premium is not provided', () => {
      it('does not render the explore premium component', () => {
        createWrapper();
        expect(findUserMenuExplorePremium().exists()).toBe(false);
      });
    });

    describe('when explore_premium is provided', () => {
      const explorePremium = { group_id: 7, requested: false };

      it('renders the explore premium component with the group id and requested props', () => {
        createWrapper({ explore_premium: explorePremium });

        expect(findUserMenuExplorePremium().props()).toMatchObject({
          groupId: explorePremium.group_id,
          requested: explorePremium.requested,
        });
      });

      it('forwards the action event to close the dropdown', () => {
        createWrapper({ explore_premium: explorePremium });
        const closeSpy = jest.fn();
        wrapper.vm.$refs.userDropdown.close = closeSpy;

        findUserMenuExplorePremium().vm.$emit('action');

        expect(closeSpy).toHaveBeenCalled();
      });

      it('calls handleMenuShown on the explore premium item when the dropdown is shown', () => {
        const handleMenuShown = jest.fn();
        createWrapper(
          { explore_premium: explorePremium },
          {
            UserMenuExplorePremium: stubComponent(UserMenuExplorePremium, {
              methods: { handleMenuShown },
            }),
          },
        );

        showDropdown();

        expect(handleMenuShown).toHaveBeenCalled();
      });
    });
  });
});
