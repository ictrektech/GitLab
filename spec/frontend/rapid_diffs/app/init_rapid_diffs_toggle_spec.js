import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import { initRapidDiffsToggle } from '~/rapid_diffs/app/init_rapid_diffs_toggle';

jest.mock('~/rapid_diffs/app/rapid_diffs_toggle.vue', () => ({
  name: 'RapidDiffsToggle',
  render(h) {
    return h('div', { attrs: { 'data-rapid-diffs-toggle': 'true' } });
  },
}));

describe('initRapidDiffsToggle', () => {
  const findToggle = () => document.querySelector('[data-rapid-diffs-toggle]');

  afterEach(() => {
    resetHTMLFixture();
  });

  it('returns null when mount element does not exist', () => {
    setHTMLFixture('<div></div>');

    expect(initRapidDiffsToggle()).toBeNull();
  });

  it('mounts the component when element exists', () => {
    setHTMLFixture(
      '<div id="js-rapid-diffs-toggle"><div class="js-rapid-diffs-toggle-mount"></div></div>',
    );

    const instance = initRapidDiffsToggle();
    expect(instance).not.toBeNull();
    expect(findToggle()).not.toBeNull();
  });
});
