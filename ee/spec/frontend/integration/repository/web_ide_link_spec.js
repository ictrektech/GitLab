import { getText, waitAndClick, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import {
  mountHeaderArea,
  findCodeDropdownToggle,
  findSshCloneItem,
  findWebIdeMenuItem,
  PROJECT_FULL_PATH,
} from './test_setup';

// The backend folds user role and merge-request access level into the
// showWebIdeButton flag (WebIdeButtonHelper#show_web_ide_button?, covered by
// its helper spec and the project policy specs); the frontend renders per flag.
describe('Code dropdown Web IDE link', () => {
  it('lists the Web IDE link when the user can contribute', async () => {
    await mountHeaderArea();
    await waitAndClick(findCodeDropdownToggle);

    const item = await waitForElement(findWebIdeMenuItem);
    const link = item.querySelector('a');

    expect(getText(link)).toContain('Web IDE');
    // Tree pages get an edit URL composed from the project path and ref.
    expect(link.getAttribute('href')).toBe(`/-/ide/project/${PROJECT_FULL_PATH}/edit/master/-/`);
    expect(link.getAttribute('target')).toBe('_blank');
  });

  it('omits the Web IDE link when the user cannot contribute', async () => {
    await mountHeaderArea({ showWebIdeButton: false });
    await waitAndClick(findCodeDropdownToggle);

    // The clone item proves the dropdown content rendered, so absence is meaningful.
    await waitForElement(findSshCloneItem);

    expect(findWebIdeMenuItem()).toBe(null);
  });
});
