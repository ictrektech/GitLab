import { GlButton, GlLink, GlIcon } from '@gitlab/ui';
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import originalRelease from 'test_fixtures/api/releases/release.json';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import { truncateSha } from '~/lib/utils/text_utility';
import EvidenceBlock from '~/releases/components/evidence_block.vue';
import ExpandButton from '~/releases/components/expand_button.vue';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';

describe('Evidence Block', () => {
  let wrapper;
  let release;

  const findExpandButton = () => wrapper.findComponent(ExpandButton).findComponent(GlButton);
  const findAllExpandButtons = () =>
    wrapper.findAllComponents(ExpandButton).wrappers.map((w) => w.findComponent(GlButton));

  const factory = (options = {}) => {
    wrapper = mount(EvidenceBlock, {
      ...options,
    });
  };

  beforeEach(() => {
    release = convertObjectPropsToCamelCase(originalRelease, { deep: true });

    factory({
      propsData: {
        release,
      },
    });
  });

  it('renders the evidence icon', () => {
    expect(wrapper.findComponent(GlIcon).props('name')).toBe('review-list');
  });

  it('renders the title for the dowload link', () => {
    expect(wrapper.findComponent(GlLink).text()).toMatch(/v1\.1-evidences-[0-9]+\.json/);
  });

  it('renders the correct hover text for the download', () => {
    expect(wrapper.findComponent(GlLink).attributes('title')).toBe('Open evidence JSON in new tab');
  });

  it('renders a link that opens in a new tab', () => {
    expect(wrapper.findComponent(GlLink).attributes().target).toBe('_blank');
  });

  describe('expand button labels', () => {
    it('includes the evidence title in the expand label', () => {
      const title = wrapper.findComponent(GlLink).text();

      expect(findExpandButton().attributes('aria-label')).toBe(
        `Expand evidence collection: ${title}`,
      );
    });

    describe('when expanded', () => {
      beforeEach(async () => {
        findExpandButton().trigger('click');
        await nextTick();
      });

      it('includes the evidence title in the collapse label', () => {
        const title = wrapper.findComponent(GlLink).text();

        expect(findExpandButton().attributes('aria-label')).toBe(
          `Collapse evidence collection: ${title}`,
        );
      });
    });

    describe('with multiple evidences', () => {
      beforeEach(() => {
        const [first] = release.evidences;

        // Explicit paths: the fixture's evidence ID is DB-assigned, so its label isn't stable.
        factory({
          propsData: {
            release: {
              ...release,
              evidences: [
                { ...first, filepath: '/group/project/-/releases/v1.1/evidences/1.json' },
                { ...first, filepath: '/group/project/-/releases/v1.1/evidences/2.json' },
              ],
            },
          },
        });
      });

      it('gives each evidence a distinct accessible name', () => {
        const labels = findAllExpandButtons().map((button) => button.attributes('aria-label'));

        expect(labels).toEqual([
          'Expand evidence collection: v1.1-evidences-1.json',
          'Expand evidence collection: v1.1-evidences-2.json',
        ]);
      });
    });
  });

  describe('sha text', () => {
    it('renders the short sha initially', () => {
      expect(wrapper.find('.js-short').text()).toBe(truncateSha(release.evidences[0].sha));
    });

    describe('when expanded', () => {
      beforeEach(async () => {
        findExpandButton().trigger('click');
        await nextTick();
      });

      it('renders the long sha', () => {
        expect(wrapper.find('.js-expanded').text()).toBe(release.evidences[0].sha);
      });
    });
  });

  describe('copy to clipboard button', () => {
    it('renders button', () => {
      expect(wrapper.findComponent(ClipboardButton).exists()).toBe(true);
    });

    it('renders the correct hover text', () => {
      expect(wrapper.findComponent(ClipboardButton).attributes('title')).toBe('Copy evidence SHA');
    });

    it('copies the sha', () => {
      expect(wrapper.findComponent(ClipboardButton).attributes('data-clipboard-text')).toBe(
        release.evidences[0].sha,
      );
    });
  });
});
