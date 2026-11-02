import MockAdapter from 'axios-mock-adapter';
import { resetHTMLFixture, setHTMLFixture } from 'helpers/fixtures';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK } from '~/lib/utils/http_status';
import apolloProvider from '~/repository/graphql';
import projectPathQuery from '~/repository/queries/project_path.query.graphql';
import refQuery from '~/repository/queries/ref.query.graphql';
import { initProfileReadme } from '~/users/profile/readme';

const WEB_PATH = '/root/root/-/blob/main/README.md';

describe('initProfileReadme', () => {
  let mockAxios;

  beforeEach(() => {
    mockAxios = new MockAdapter(axios);
    mockAxios.onGet(WEB_PATH).reply(HTTP_STATUS_OK, { html: '<p>Hello from my README</p>' });
  });

  afterEach(() => {
    mockAxios.restore();
    resetHTMLFixture();
  });

  it('returns null when the mount element does not exist', () => {
    setHTMLFixture('<div></div>');

    expect(initProfileReadme()).toBeNull();
  });

  describe('when the mount element exists', () => {
    beforeEach(() => {
      setHTMLFixture(`
        <div
          id="js-profile-readme"
          data-project-path="root/root"
          data-ref="main"
          data-escaped-ref="main"
          data-name="README.md"
          data-path="README.md"
          data-web-path="${WEB_PATH}"
        ></div>
      `);

      initProfileReadme();
      return waitForPromises();
    });

    it('writes the project path and ref to the Apollo cache', () => {
      const { cache } = apolloProvider.clients.defaultClient;

      expect(cache.readQuery({ query: projectPathQuery })).toEqual({ projectPath: 'root/root' });
      expect(cache.readQuery({ query: refQuery })).toEqual({ ref: 'main', escapedRef: 'main' });
    });

    it('renders the README with the repository preview component', () => {
      expect(document.querySelector('.readme-holder').textContent).toContain('README.md');
      expect(document.body.textContent).toContain('Hello from my README');
    });
  });
});
