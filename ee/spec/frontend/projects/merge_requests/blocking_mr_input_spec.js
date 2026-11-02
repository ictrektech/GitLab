import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import initBlockingMrInput from 'ee/projects/merge_requests/blocking_mr_input';

jest.mock('~/lib/utils/vue3compat/init_vue_app');

describe('BlockingMrInput', () => {
  const refs = ['!1'];
  const getProps = () => initVueApp.mock.calls[0][0].props;
  const setInnerHtml = (visibleMrs = refs, hiddenCount = 2) => {
    document.body.innerHTML += `<div id="test" data-hidden-blocking-mrs-count="${hiddenCount}" data-visible-blocking-mr-refs='${JSON.stringify(
      visibleMrs,
    )}'></div>`;
  };

  afterEach(() => {
    document.querySelector('#test').remove();
  });

  it('adds hidden references block when hidden count is greater than 0', () => {
    setInnerHtml();
    initBlockingMrInput(document.querySelector('#test'));

    expect(getProps().existingRefs).toEqual([
      '!1',
      { text: '2 inaccessible merge requests', isHiddenRef: true },
    ]);
  });

  it('containsHiddenBlockingMrs is true when count is greater than one', () => {
    setInnerHtml();
    initBlockingMrInput(document.querySelector('#test'));

    expect(getProps().containsHiddenBlockingMrs).toBe(true);
  });

  it('containsHiddenBlockingMrs is false when count is zero', () => {
    setInnerHtml(refs, 0);
    initBlockingMrInput(document.querySelector('#test'));

    expect(getProps().containsHiddenBlockingMrs).toBe(false);
    expect(getProps().existingRefs).toEqual(['!1']);
  });
});
