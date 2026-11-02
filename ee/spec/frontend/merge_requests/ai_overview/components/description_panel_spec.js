import { nextTick } from 'vue';
import { GlAvatar, GlLink } from '@gitlab/ui';
import { trimText } from 'helpers/text_helper';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import { renderGFM } from '~/behaviors/markdown/render_gfm';
import DescriptionPanel from 'ee/merge_requests/ai_overview/components/description_panel.vue';
import { makeMergeRequest } from '../mock_data';

jest.mock('~/behaviors/markdown/render_gfm');

describe('AI Overview description panel', () => {
  let wrapper;

  const createComponent = (overrides = {}, slots = {}) => {
    wrapper = mountExtended(DescriptionPanel, {
      propsData: { mergeRequest: makeMergeRequest(overrides) },
      slots,
    });
  };

  const findContent = () => wrapper.findByTestId('description-content');
  const findAuthor = () => wrapper.findByTestId('description-author');
  const findAuthorLink = () => findAuthor().findComponent(GlLink);

  describe('with a description', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the description HTML as markdown', () => {
      expect(findContent().classes()).toContain('md');
      expect(findContent().html()).toContain('<p data-sourcepos="1:1-1:19" dir="auto">');
      expect(findContent().text()).toBe('Adds rate limiting.');
    });

    it('runs the GFM renderer over the description', () => {
      expect(renderGFM).toHaveBeenCalledWith(findContent().element);
    });

    it('names the author', () => {
      expect(trimText(findAuthor().text())).toBe('Created by Priya Nair');
    });

    it('links the author to their profile with a user popover', () => {
      expect(findAuthorLink().attributes()).toMatchObject({
        href: '/priya',
        'data-user-id': '1',
        'data-username': 'priya',
      });
      expect(findAuthorLink().classes()).toContain('js-user-link');
      expect(findAuthorLink().findComponent(GlAvatar).props('src')).toBe('/priya.png');
    });
  });

  describe('without a description', () => {
    beforeEach(() => {
      createComponent({ descriptionHtml: '' });
    });

    it('says there is no description', () => {
      expect(findContent().exists()).toBe(false);
      expect(wrapper.text()).toContain('No description');
    });

    it('does not run the GFM renderer', () => {
      expect(renderGFM).not.toHaveBeenCalled();
    });
  });

  it('shows what it is given, like the risk assessment, above the header', () => {
    createComponent({}, { default: '<div data-testid="nested-row"></div>' });

    const nested = wrapper.findByTestId('nested-row').element;

    expect(nested.previousElementSibling).toBeNull();
    expect(nested.nextElementSibling.textContent).toContain('Description');
  });

  it('leaves the author out when there is none', () => {
    createComponent({ author: null });

    expect(findAuthor().exists()).toBe(false);
    expect(findContent().exists()).toBe(true);
  });

  describe('truncating', () => {
    const LONG = 345;
    const SHORT = 344;
    const headingHtml = '<h2 id="user-content-setup">Setup</h2><p>Run the migration.</p>';

    const findReadMore = () => wrapper.findByTestId('description-read-more');
    const isTruncated = () => findContent().classes().includes('gl-overflow-hidden');
    const mockContentHeight = (height) =>
      jest.spyOn(Element.prototype, 'scrollHeight', 'get').mockReturnValue(height);
    const loadImage = async () => {
      // Image load events do not bubble, so this reaches the panel only in the capture phase.
      findContent().element.firstElementChild.dispatchEvent(new Event('load'));
      await nextTick();
    };

    afterEach(() => {
      setWindowLocation('#');
    });

    it('shows a short description in full', async () => {
      mockContentHeight(SHORT);
      createComponent();
      await nextTick();

      expect(isTruncated()).toBe(false);
      expect(findReadMore().exists()).toBe(false);
    });

    describe('with a long description', () => {
      beforeEach(async () => {
        mockContentHeight(LONG);
        createComponent();
        await nextTick();
      });

      it('fades it out under Read more', () => {
        expect(findContent().classes()).toEqual(
          expect.arrayContaining(['gl-max-h-31', 'gl-overflow-hidden']),
        );
        expect(findReadMore().text()).toBe('Read more');
      });

      it('shows the rest from Read more, and keeps it shown as images load', async () => {
        await findReadMore().trigger('click');
        await loadImage();

        expect(isTruncated()).toBe(false);
        expect(findReadMore().exists()).toBe(false);
      });
    });

    it('fades a description that grows past the limit once its images load', async () => {
      const height = mockContentHeight(SHORT);
      createComponent();
      height.mockReturnValue(LONG);
      await loadImage();

      expect(isTruncated()).toBe(true);
    });

    it('renders and measures a changed description again', async () => {
      const height = mockContentHeight(SHORT);
      const renderedHtml = [];
      renderGFM.mockImplementation((el) => renderedHtml.push(el.innerHTML));
      createComponent();
      height.mockReturnValue(LONG);
      await wrapper.setProps({ mergeRequest: makeMergeRequest({ descriptionHtml: headingHtml }) });
      await nextTick();
      await nextTick();

      expect(renderGFM).toHaveBeenCalledTimes(2);
      expect(renderedHtml[1]).toBe(headingHtml);
      expect(isTruncated()).toBe(true);
    });

    it('shows a long description in full when the page links to a heading inside it', async () => {
      setWindowLocation('#setup');
      mockContentHeight(LONG);
      createComponent({ descriptionHtml: headingHtml });
      await nextTick();

      expect(isTruncated()).toBe(false);
    });

    describe('when the link changes to a heading hidden by the fade', () => {
      beforeEach(async () => {
        Element.prototype.scrollIntoView = jest.fn();
        mockContentHeight(LONG);
        createComponent({ descriptionHtml: headingHtml });
        await nextTick();
      });

      afterEach(() => {
        delete Element.prototype.scrollIntoView;
      });

      it('shows the rest and scrolls to the heading', async () => {
        setWindowLocation('#setup');
        window.dispatchEvent(new HashChangeEvent('hashchange'));
        await nextTick();
        await nextTick();

        expect(isTruncated()).toBe(false);
        expect(Element.prototype.scrollIntoView).toHaveBeenCalledTimes(1);
      });

      it('leaves it faded for a link to somewhere else', async () => {
        setWindowLocation('#note_1');
        window.dispatchEvent(new HashChangeEvent('hashchange'));
        await nextTick();

        expect(isTruncated()).toBe(true);
        expect(Element.prototype.scrollIntoView).not.toHaveBeenCalled();
      });
    });
  });
});
