import { GlDrawer } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { renderGFM } from '~/behaviors/markdown/render_gfm';
import { destroyImageLightbox } from '~/behaviors/markdown/render_image_lightbox';
import ReadinessDrawer from 'ee/work_items/components/implementation_widget/readiness_drawer.vue';

jest.mock('~/behaviors/markdown/render_gfm');
jest.mock('~/behaviors/markdown/render_image_lightbox');

const FEEDBACK_HTML =
  '<ol><li><strong>Add acceptance criteria.</strong></li></ol><p>Describe the expected behavior.</p>';

describe('ReadinessDrawer', () => {
  let wrapper;

  const findRenderedFeedback = () => wrapper.findByTestId('readiness-feedback-rendered');
  const findLoadingFeedback = () => wrapper.findByTestId('readiness-feedback-loading');
  const findStatus = () => wrapper.findByTestId('readiness-feedback-status');

  const createComponent = (props = {}) => {
    wrapper = mountExtended(ReadinessDrawer, {
      propsData: {
        isOpen: true,
        feedbackHtml: FEEDBACK_HTML,
        isLoading: false,
        hasError: false,
        ...props,
      },
      attachTo: document.body,
    });
  };

  describe('with feedback', () => {
    beforeEach(() => createComponent());

    it('renders the readiness headings, explanation, and markdown', () => {
      expect(wrapper.findByRole('heading', { name: 'Readiness', level: 2 }).exists()).toBe(true);
      expect(
        wrapper.findByRole('heading', { name: 'How to improve readiness', level: 3 }).exists(),
      ).toBe(true);
      expect(wrapper.text()).toContain(
        'GitLab Duo reviewed this work item and suggests these changes:',
      );
      expect(wrapper.findByRole('heading', { name: 'What is readiness?' }).exists()).toBe(true);
      expect(wrapper.findByRole('link', { name: 'Learn more' }).attributes('href')).toMatch(
        /#readiness$/,
      );
      expect(wrapper.find('ol li strong').text()).toBe('Add acceptance criteria.');
      expect(wrapper.text()).toContain('Describe the expected behavior.');
    });

    it('applies GFM behaviors to the rendered feedback', async () => {
      await nextTick();
      expect(renderGFM).toHaveBeenCalledWith(findRenderedFeedback().element);
    });

    it('re-applies GFM behaviors when the feedback changes', async () => {
      renderGFM.mockClear();
      await wrapper.setProps({ feedbackHtml: '<p>New assessment</p>' });
      await nextTick();
      expect(findRenderedFeedback().text()).toBe('New assessment');
      expect(renderGFM).toHaveBeenCalledWith(findRenderedFeedback().element);
    });

    it('releases the image lightbox when the drawer closes', async () => {
      const { element } = findRenderedFeedback();
      await wrapper.setProps({ isOpen: false });
      expect(destroyImageLightbox).toHaveBeenCalledWith(element);
    });

    it('focuses the heading when the drawer opens', async () => {
      await wrapper.findComponent(GlDrawer).vm.$emit('opened');
      expect(document.activeElement).toBe(
        wrapper.findByRole('heading', { name: 'Readiness', level: 2 }).element,
      );
    });

    it('closes on Escape', () => {
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', keyCode: 27 }));
      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    it('closes even when a global shortcut prevents the Escape default', () => {
      const event = new KeyboardEvent('keydown', { key: 'Escape', keyCode: 27, cancelable: true });
      event.preventDefault();
      document.dispatchEvent(event);
      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    it('closes using the panel close button', async () => {
      await wrapper.findByRole('button', { name: 'Close drawer' }).trigger('click');
      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });

  describe.each([null, '', '   '])('with empty feedback %p', (feedbackHtml) => {
    beforeEach(() => createComponent({ feedbackHtml }));

    it('renders only the drawer title and readiness explanation', () => {
      expect(wrapper.findByRole('heading', { name: 'Readiness', level: 2 }).exists()).toBe(true);
      expect(wrapper.findByRole('heading', { name: 'How to improve readiness' }).exists()).toBe(
        false,
      );
      expect(findRenderedFeedback().exists()).toBe(false);
      expect(wrapper.text()).not.toContain('GitLab Duo reviewed this work item');
      expect(wrapper.findByRole('heading', { name: 'What is readiness?' }).exists()).toBe(true);
    });
  });

  describe('while feedback is loading', () => {
    beforeEach(() => createComponent({ feedbackHtml: null, isLoading: true }));

    it('announces loading and keeps the explanation visible', () => {
      expect(findStatus().attributes('role')).toBe('status');
      expect(findStatus().text()).toBe('Loading readiness details');
      expect(findLoadingFeedback().attributes('aria-hidden')).toBe('true');
      expect(findRenderedFeedback().exists()).toBe(false);
      expect(wrapper.findByRole('heading', { name: 'What is readiness?' }).exists()).toBe(true);
    });

    it('replaces the skeleton with formatted feedback after loading', async () => {
      await wrapper.setProps({ isLoading: false, feedbackHtml: FEEDBACK_HTML });
      await nextTick();

      expect(findLoadingFeedback().exists()).toBe(false);
      expect(findStatus().text()).toBe('');
      expect(findRenderedFeedback().text()).toContain('Add acceptance criteria.');
      expect(renderGFM).toHaveBeenCalledWith(findRenderedFeedback().element);
    });
  });

  describe('while refreshing existing feedback', () => {
    beforeEach(() => createComponent({ isLoading: true }));

    it('keeps feedback visible without showing a skeleton', () => {
      expect(findRenderedFeedback().text()).toContain('Add acceptance criteria.');
      expect(findLoadingFeedback().exists()).toBe(false);
    });
  });

  describe('after feedback fails to load', () => {
    beforeEach(() => createComponent({ feedbackHtml: null, hasError: true }));

    it('does not put the Duo icon on Try again, which only reloads the feedback', () => {
      expect(wrapper.findByRole('button', { name: 'Try again' }).find('svg').exists()).toBe(false);
    });

    it('shows an inline error and allows retrying', async () => {
      expect(wrapper.findByRole('alert').text()).toContain(
        'Readiness details could not be loaded.',
      );
      expect(findLoadingFeedback().exists()).toBe(false);
      expect(wrapper.findByRole('heading', { name: 'What is readiness?' }).exists()).toBe(true);

      await wrapper.findByRole('button', { name: 'Try again' }).trigger('click');
      expect(wrapper.emitted('retry')).toHaveLength(1);
      expect(document.activeElement).toBe(
        wrapper.findByRole('heading', { name: 'Readiness', level: 2 }).element,
      );
    });
  });

  describe('after refreshing existing feedback fails', () => {
    beforeEach(() => createComponent({ hasError: true }));

    it('shows the error alongside the last loaded feedback', () => {
      expect(wrapper.findByRole('alert').text()).toContain(
        'Readiness details could not be loaded.',
      );
      expect(findRenderedFeedback().text()).toContain('Add acceptance criteria.');
      expect(findLoadingFeedback().exists()).toBe(false);
    });
  });

  describe('with untrusted HTML #security', () => {
    beforeEach(() =>
      createComponent({
        feedbackHtml:
          '<script>alert(1)</script><img src=x onerror="alert(1)"><a href="javascript:alert(1)">unsafe</a>',
      }),
    );

    it('removes executable HTML and unsafe links', () => {
      expect(wrapper.find('script').exists()).toBe(false);
      expect(wrapper.find('[onerror]').exists()).toBe(false);
      expect(wrapper.find('a[href^="javascript:"]').exists()).toBe(false);
    });
  });
});
