import { nextTick } from 'vue';
import { GlButton } from '@gitlab/ui';
import setWindowLocation from 'helpers/set_window_location_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { handleLocationHash } from '~/lib/utils/common_utils';
import FilePreview from '~/repository/components/preview/index.vue';
import ProfileReadme, {
  READ_MORE_HEIGHT,
} from '~/users/profile/readme/components/profile_readme.vue';

jest.mock('~/lib/utils/common_utils');

const BLOB = { name: 'README.md', path: 'README.md', webPath: '/root/root/-/blob/main/README.md' };

describe('ProfileReadme', () => {
  let wrapper;

  const findContent = () => wrapper.findByTestId('profile-readme-content');
  const findReadMore = () => wrapper.findByTestId('profile-readme-read-more');
  const findFilePreview = () => wrapper.findComponent(FilePreview);

  const createComponent = () => {
    wrapper = shallowMountExtended(ProfileReadme, {
      propsData: { blob: BLOB },
      stubs: { GlButton },
      attachTo: document.body,
    });
  };

  const renderReadme = async ({ scrollHeight, html = '' }) => {
    const contentEl = findContent().element;
    contentEl.insertAdjacentHTML('beforeend', html);
    jest.spyOn(contentEl, 'scrollHeight', 'get').mockReturnValue(scrollHeight);

    findFilePreview().vm.$emit('rendered');
    await nextTick();
  };

  it('renders the repository preview', () => {
    createComponent();

    expect(findFilePreview().props()).toMatchObject({ blob: BLOB });
  });

  it('limits the content height and hides "Read more" before the README is rendered', () => {
    createComponent();

    expect(findContent().attributes('style')).toContain(`max-height: ${READ_MORE_HEIGHT}px`);
    expect(findReadMore().exists()).toBe(false);
  });

  describe('when the README is shorter than the limit', () => {
    beforeEach(async () => {
      createComponent();
      await renderReadme({ scrollHeight: READ_MORE_HEIGHT - 1 });
    });

    it('does not render "Read more"', () => {
      expect(findReadMore().exists()).toBe(false);
    });
  });

  describe('when the README is taller than the limit', () => {
    beforeEach(async () => {
      createComponent();
      await renderReadme({ scrollHeight: READ_MORE_HEIGHT + 1 });
    });

    it('renders "Read more"', () => {
      expect(findReadMore().exists()).toBe(true);
      expect(findReadMore().findComponent(GlButton).attributes('aria-label')).toBe('Expand Readme');
    });

    it('expands the content when "Read more" is clicked', async () => {
      findReadMore().findComponent(GlButton).vm.$emit('click');
      await nextTick();

      expect(findReadMore().exists()).toBe(false);
      expect(findContent().attributes('style') ?? '').not.toContain('max-height');
    });
  });

  describe('when the URL hash points into the README', () => {
    beforeEach(async () => {
      setWindowLocation('#installation');
      createComponent();
      await renderReadme({
        scrollHeight: READ_MORE_HEIGHT + 1,
        html: '<h2 id="user-content-installation">Installation</h2>',
      });
    });

    it('expands the content and scrolls to the anchor', async () => {
      await nextTick();

      expect(findReadMore().exists()).toBe(false);
      expect(findContent().attributes('style') ?? '').not.toContain('max-height');
      expect(handleLocationHash).toHaveBeenCalled();
    });
  });

  describe('when the URL hash is malformed', () => {
    beforeEach(async () => {
      setWindowLocation('#%E0%A4%A');
      createComponent();
      await renderReadme({ scrollHeight: READ_MORE_HEIGHT + 1 });
    });

    it('treats it as no target and still renders "Read more"', () => {
      expect(findReadMore().exists()).toBe(true);
      expect(handleLocationHash).not.toHaveBeenCalled();
    });
  });
});
