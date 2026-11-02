import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { initSecurityConfiguration } from 'ee/security_configuration';

Vue.use(VueApollo);

describe('initSecurityConfiguration', () => {
  let app;

  const createEl = (scanCoverageBanner) => {
    const el = document.createElement('div');
    Object.assign(el.dataset, {
      groupFullPath: 'group',
      groupId: '7',
      groupName: 'Group',
      rootGroupName: 'Root',
      namespaceId: '1',
      securityInventoryPath: '/inventory',
      canReadAttributes: 'false',
      canManageAttributes: 'false',
      canReadScanProfiles: 'false',
      canApplyProfiles: 'false',
      ...(scanCoverageBanner !== undefined && { scanCoverageBanner }),
    });
    document.body.appendChild(el);
    return el;
  };

  afterEach(() => {
    app?.$destroy();
    app = null;
  });

  it('returns null when el is not provided', () => {
    expect(initSecurityConfiguration(null)).toBe(null);
    expect(initSecurityConfiguration(undefined)).toBe(null);
  });

  it('provides scanCoverageBanner as null when the dataset value is the string "null"', () => {
    app = initSecurityConfiguration(createEl('null'));

    expect(app.$options.provide.scanCoverageBanner).toBeNull();
  });

  it('provides the parsed scanCoverageBanner object', () => {
    const payload = { variant: 'warning', title: 'No projects are scanned yet' };

    app = initSecurityConfiguration(createEl(JSON.stringify(payload)));

    expect(app.$options.provide.scanCoverageBanner).toEqual(payload);
  });

  it('provides scanCoverageBanner as null when the dataset value is malformed JSON', () => {
    app = initSecurityConfiguration(createEl('{not valid json'));

    expect(app.$options.provide.scanCoverageBanner).toBeNull();
  });

  it('provides scanCoverageBanner as null when the dataset attribute is missing', () => {
    app = initSecurityConfiguration(createEl(undefined));

    expect(app.$options.provide.scanCoverageBanner).toBeNull();
  });
});
