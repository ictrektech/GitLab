import {
  initOrganizationAccess,
  initOrganizationAccessArtifactRegistry,
} from 'ee/organizations/access';
import { resetHTMLFixture, setHTMLFixture } from 'helpers/fixtures';
import waitForPromises from 'helpers/wait_for_promises';

describe('initOrganizationAccess', () => {
  afterEach(() => {
    resetHTMLFixture();
  });

  it('returns false when the mount element is missing', () => {
    expect(initOrganizationAccess()).toBe(false);
  });

  it('mounts the app with the organization path', async () => {
    setHTMLFixture('<div id="js-organization-access" data-organization-path="my-org"></div>');

    initOrganizationAccess();
    await waitForPromises();

    expect(document.body.textContent).toContain('Organization access');
    expect(document.body.textContent).toContain('5 members');
    expect(document.body.textContent).toContain('Alex Garcia');
    expect(document.querySelector('a[href="/o/my-org/-/access/artifact-registry"]')).not.toBeNull();
  });
});

describe('initOrganizationAccessArtifactRegistry', () => {
  afterEach(() => {
    resetHTMLFixture();
  });

  it('returns false when the mount element is missing', () => {
    expect(initOrganizationAccessArtifactRegistry()).toBe(false);
  });

  it('mounts the Artifact Registry members page with the mock members', async () => {
    setHTMLFixture(
      '<div id="js-organization-access-artifact-registry" data-organization-path="my-org"></div>',
    );

    initOrganizationAccessArtifactRegistry();
    await waitForPromises();

    expect(document.querySelector('h1').textContent.trim()).toBe('Artifact Registry');
    expect(document.body.textContent).toContain('Alex Garcia');
  });
});
