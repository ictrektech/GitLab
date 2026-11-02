import { shallowMount } from '@vue/test-utils';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import DivergenceGraph from '~/branches/components/divergence_graph.vue';
import GraphBar from '~/branches/components/graph_bar.vue';

let vm;

function factory(propsData = {}) {
  vm = shallowMount(DivergenceGraph, {
    propsData,
    directives: { GlTooltip: createMockDirective('gl-tooltip') },
  });
}

describe('Branch divergence graph component', () => {
  it('renders ahead and behind count', () => {
    factory({
      defaultBranch: 'main',
      aheadCount: 10,
      behindCount: 10,
      maxCommits: 100,
    });

    expect(vm.findAllComponents(GraphBar)).toHaveLength(2);
    expect(vm.element).toMatchSnapshot();
  });

  it('renders a focusable button with a tooltip', () => {
    factory({
      defaultBranch: 'main',
      aheadCount: 10,
      behindCount: 10,
      maxCommits: 100,
    });

    expect(vm.element.tagName).toBe('BUTTON');
    expect(vm.attributes('type')).toBe('button');
    expect(getBinding(vm.element, 'gl-tooltip')).toBeDefined();
  });

  it('sets title for ahead and behind count', () => {
    factory({
      defaultBranch: 'main',
      aheadCount: 10,
      behindCount: 10,
      maxCommits: 100,
    });

    expect(vm.attributes('title')).toBe('10 commits behind main, 10 commits ahead');
    expect(vm.find('.gl-sr-only').text()).toBe('10 commits behind main, 10 commits ahead');
  });

  it('renders distance count', () => {
    factory({
      defaultBranch: 'main',
      aheadCount: 0,
      behindCount: 0,
      distance: 900,
      maxCommits: 100,
    });

    expect(vm.findAllComponents(GraphBar)).toHaveLength(1);
    expect(vm.findComponent(GraphBar).attributes('aria-hidden')).toBe('true');
    expect(vm.element).toMatchSnapshot();
  });

  it.each`
    distance | titleText
    ${900}   | ${'900'}
    ${1100}  | ${'999+'}
  `('sets title for $distance as $titleText', ({ distance, titleText }) => {
    factory({
      defaultBranch: 'main',
      aheadCount: 0,
      behindCount: 0,
      distance,
      maxCommits: 100,
    });

    expect(vm.attributes('title')).toBe(`More than ${titleText} commits different with main`);
    expect(vm.find('.gl-sr-only').text()).toBe(
      `More than ${titleText} commits different with main`,
    );
  });
});
