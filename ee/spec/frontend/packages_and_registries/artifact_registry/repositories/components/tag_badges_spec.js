import { GlBadge, GlPopover } from '@gitlab/ui';
import { queryByRole, within } from '@testing-library/dom';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import TagBadges from 'ee/packages_and_registries/artifact_registry/repositories/components/tag_badges.vue';

describe('ArtifactRegistryTagBadges', () => {
  let wrapper;
  let container;

  const createComponent = (tags) => {
    container = document.createElement('div');
    container.appendChild(document.createElement('div'));

    wrapper = mountExtended(TagBadges, {
      propsData: { tags },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
      attachTo: container.firstChild,
    });
  };

  const findTagList = () => queryByRole(container, 'list', { name: 'Tags' });
  const findTags = () => wrapper.findAllByTestId('tag-badge');
  const findTagNames = () => findTags().wrappers.map((tag) => tag.text());
  const findMoreTags = () => wrapper.findByTestId('tag-badges-more');
  const findCollapsedTags = () => wrapper.findAllByTestId('tag-badges-collapsed');

  it('renders the tags in the order given, without sorting them itself', () => {
    createComponent(['v2', 'latest', 'alpha']);

    expect(findTagNames()).toEqual(['v2', 'latest', 'alpha']);
  });

  it('renders each tag with the info variant', () => {
    createComponent(['latest']);

    expect(wrapper.findComponent(GlBadge).props('variant')).toBe('info');
  });

  it('exposes the tags to a screen reader as a named list of items', () => {
    createComponent(['latest', 'next']);

    const items = within(findTagList()).getAllByRole('listitem');

    expect(items.map((item) => item.textContent.trim())).toEqual(['latest', 'next']);
  });

  it.each`
    case               | tags
    ${'an empty list'} | ${[]}
    ${'no list'}       | ${undefined}
  `('renders no row at all for $case', ({ tags }) => {
    createComponent(tags);

    expect(findTags()).toHaveLength(0);
    expect(findTagList()).toBeNull();
  });

  describe('a tag name longer than the row can carry', () => {
    const LONG_TAG = 'a'.repeat(128);

    beforeEach(() => {
      createComponent([LONG_TAG]);
    });

    it('truncates it rather than letting it overflow the row', () => {
      expect(findTagNames()[0]).toHaveLength(32);
      expect(findTagNames()[0]).not.toBe(LONG_TAG);
    });

    it('keeps the whole name reachable in a tooltip', () => {
      expect(getBinding(findTags().at(0).element, 'gl-tooltip').value).toBe(LONG_TAG);
    });
  });

  it('leaves a short name untouched, with no tooltip to dismiss', () => {
    createComponent(['latest']);

    expect(findTagNames()).toEqual(['latest']);
    expect(getBinding(findTags().at(0).element, 'gl-tooltip').value).toBe(null);
  });

  describe('when there are more tags than the row shows', () => {
    const MANY = Array.from({ length: 12 }, (_, index) => `v${index}`);

    beforeEach(() => {
      createComponent(MANY);
    });

    it('renders only the first five in the row', () => {
      expect(findTagNames()).toEqual(['v0', 'v1', 'v2', 'v3', 'v4']);
    });

    it('counts the rest rather than dropping them silently', () => {
      expect(findMoreTags().text()).toBe('+7 more');
    });

    it('exposes the count as a real button', () => {
      expect(queryByRole(container, 'button', { name: '+7 more' })).not.toBeNull();
      expect(findMoreTags().attributes('role')).toBeUndefined();
    });

    it('keeps every remaining tag reachable in the popover', () => {
      const popover = wrapper.findComponent(GlPopover);

      expect(popover.props('target')).toBe(findMoreTags().attributes('id'));
      expect(popover.props('title')).toBe('All tags');
      expect(findCollapsedTags().wrappers.map((tag) => tag.text())).toEqual([
        'v5',
        'v6',
        'v7',
        'v8',
        'v9',
        'v10',
        'v11',
      ]);
    });
  });

  it('renders no overflow affordance when every tag fits', () => {
    createComponent(['a', 'b']);

    expect(findMoreTags().exists()).toBe(false);
  });
});
