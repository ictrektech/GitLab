import { shallowMount } from '@vue/test-utils';
import SecurityConfigurationAppEE from 'ee/security_configuration/components/app.vue';
import SecurityConfigurationApp from '~/security_configuration/components/app.vue';

describe('SecurityConfigurationAppEE', () => {
  let wrapper;

  describe('when the initializer passes props through a render function', () => {
    const appStub = {
      props: SecurityConfigurationApp.props,
      template: '<div></div>',
    };

    beforeEach(() => {
      wrapper = shallowMount(
        {
          components: { SecurityConfigurationAppEE },
          render(createElement) {
            return createElement('SecurityConfigurationAppEE', {
              props: {
                augmentedSecurityFeatures: [{ name: 'SAST' }],
                securityTrainingEnabled: true,
                mergeRequestsEnabled: false,
              },
            });
          },
        },
        {
          stubs: { SecurityConfigurationAppEE, SecurityConfigurationApp: appStub },
        },
      );
    });

    it('forwards required and optional props to the shared app', () => {
      expect(wrapper.findComponent(appStub).props()).toMatchObject({
        augmentedSecurityFeatures: [{ name: 'SAST' }],
        securityTrainingEnabled: true,
        mergeRequestsEnabled: false,
      });
    });
  });

  describe.each`
    archival     | tracking     | archivesAvailable | refsAvailable
    ${true}      | ${true}      | ${true}           | ${true}
    ${true}      | ${false}     | ${true}           | ${false}
    ${false}     | ${true}      | ${false}          | ${true}
    ${false}     | ${false}     | ${false}          | ${false}
    ${undefined} | ${undefined} | ${false}          | ${false}
  `(
    'when archival is $archival and ref tracking is $tracking',
    ({ archival, tracking, archivesAvailable, refsAvailable }) => {
      beforeEach(() => {
        wrapper = shallowMount(SecurityConfigurationAppEE, {
          propsData: {
            augmentedSecurityFeatures: [{ name: 'SAST' }],
            securityTrainingEnabled: true,
            mergeRequestsEnabled: false,
          },
          provide: {
            projectFullPath: 'group/project',
            glFeatures: {
              vulnerabilityArchival: archival,
              vulnerabilitiesAcrossContexts: tracking,
            },
          },
          stubs: {
            SecurityConfigurationApp: {
              props: SecurityConfigurationApp.props,
              inject: ['vulnerabilityArchivesAvailable', 'refTrackingAvailable', 'projectFullPath'],
              template:
                '<div>{{ vulnerabilityArchivesAvailable }} {{ refTrackingAvailable }} {{ projectFullPath }}</div>',
            },
          },
        });
      });

      it('provides independent capabilities and preserves ancestor injections', () => {
        expect(wrapper.text()).toBe(`${archivesAvailable} ${refsAvailable} group/project`);
      });

      it('forwards the app inputs', () => {
        expect(wrapper.findComponent(SecurityConfigurationApp).props()).toMatchObject({
          augmentedSecurityFeatures: [{ name: 'SAST' }],
          securityTrainingEnabled: true,
          mergeRequestsEnabled: false,
        });
      });
    },
  );
});
