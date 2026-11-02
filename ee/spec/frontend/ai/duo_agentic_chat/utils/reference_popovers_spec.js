import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import { TEST_HOST } from 'helpers/test_constants';
import waitForPromises from 'helpers/wait_for_promises';
import { handleIssuablePopoverMount } from '~/issuable/popover';
import {
  parseReferenceUrl,
  initChatReferencePopovers,
} from 'ee/ai/duo_agentic_chat/utils/reference_popovers';

jest.mock('~/lib/graphql');
jest.mock('~/issuable/popover');

const findByTestId = (testId) => document.querySelector(`[data-testid="${testId}"]`);
const findRoot = () => findByTestId('root');
const findIssueLink = () => findByTestId('issue-link');

const triggerMouseover = (el) => {
  el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
};

const triggerMouseenter = (el) => {
  el.dispatchEvent(new MouseEvent('mouseenter'));
};

const triggerMouseleave = (el) => {
  el.dispatchEvent(new MouseEvent('mouseleave'));
};

const triggerFocusin = (el) => {
  el.dispatchEvent(new FocusEvent('focusin', { bubbles: true }));
};

const triggerFocusout = (el) => {
  el.dispatchEvent(new FocusEvent('focusout', { bubbles: true }));
};

describe('reference_popovers', () => {
  describe('parseReferenceUrl', () => {
    it.each`
      description             | href                                                       | expected
      ${'project issue'}      | ${`${TEST_HOST}/group/project/-/issues/12`}                | ${{ referenceType: 'issue', namespacePath: 'group/project', iid: '12' }}
      ${'project work item'}  | ${`${TEST_HOST}/group/project/-/work_items/12`}            | ${{ referenceType: 'work_item', namespacePath: 'group/project', iid: '12' }}
      ${'merge request'}      | ${`${TEST_HOST}/group/project/-/merge_requests/3`}         | ${{ referenceType: 'merge_request', namespacePath: 'group/project', iid: '3' }}
      ${'group epic'}         | ${`${TEST_HOST}/groups/group/-/epics/5`}                   | ${{ referenceType: 'epic', namespacePath: 'group', iid: '5' }}
      ${'group work item'}    | ${`${TEST_HOST}/groups/group/sub/-/work_items/7`}          | ${{ referenceType: 'work_item', namespacePath: 'group/sub', iid: '7' }}
      ${'commit'}             | ${`${TEST_HOST}/group/project/-/commit/abc123de`}          | ${{ referenceType: 'commit', projectPath: 'group/project', commitSha: 'abc123de' }}
      ${'uppercase commit'}   | ${`${TEST_HOST}/group/project/-/commit/ABC123DE`}          | ${{ referenceType: 'commit', projectPath: 'group/project', commitSha: 'ABC123DE' }}
      ${'SHA-256 commit'}     | ${`${TEST_HOST}/group/project/-/commit/${'a'.repeat(64)}`} | ${{ referenceType: 'commit', projectPath: 'group/project', commitSha: 'a'.repeat(64) }}
      ${'query and fragment'} | ${`${TEST_HOST}/group/project/-/issues/12?x=1#top`}        | ${{ referenceType: 'issue', namespacePath: 'group/project', iid: '12' }}
    `('resolves a $description link', ({ href, expected }) => {
      expect(parseReferenceUrl(href)).toEqual(expected);
    });

    it.each`
      description                      | href
      ${'cross-origin'}                | ${'https://example.com/group/project/-/issues/12'}
      ${'non-reference route'}         | ${`${TEST_HOST}/group/project/-/pipelines/12`}
      ${'sub-route'}                   | ${`${TEST_HOST}/group/project/-/merge_requests/3/diffs`}
      ${'milestone'}                   | ${`${TEST_HOST}/group/project/-/milestones/1`}
      ${'missing namespace'}           | ${`${TEST_HOST}/-/issues/12`}
      ${'new issue form'}              | ${`${TEST_HOST}/group/project/-/issues/new`}
      ${'non-hex commit ref'}          | ${`${TEST_HOST}/group/project/-/commit/main`}
      ${'group-level commit'}          | ${`${TEST_HOST}/groups/group/-/commit/abc123de`}
      ${'plain project page'}          | ${`${TEST_HOST}/group/project`}
      ${'group merge request'}         | ${`${TEST_HOST}/groups/group/-/merge_requests/3`}
      ${'project epic'}                | ${`${TEST_HOST}/group/project/-/epics/5`}
      ${'relative non-reference path'} | ${'not a url'}
      ${'malformed URL'}               | ${'http://['}
    `('returns null for a $description link', ({ href }) => {
      expect(parseReferenceUrl(href)).toBeNull();
    });

    describe('when GitLab runs under a relative URL root', () => {
      beforeEach(() => {
        window.gon.relative_url_root = '/gitlab';
      });

      it('strips the root from the namespace path', () => {
        expect(parseReferenceUrl(`${TEST_HOST}/gitlab/group/project/-/issues/12`)).toEqual({
          referenceType: 'issue',
          namespacePath: 'group/project',
          iid: '12',
        });
      });
    });
  });

  describe('initChatReferencePopovers', () => {
    let popovers;
    let dispose;

    const hover = async (el) => {
      triggerMouseover(el);
      await waitForPromises();
    };
    const focus = async (el) => {
      triggerFocusin(el);
      await waitForPromises();
    };
    const waitForMountDelay = () => jest.advanceTimersByTime(200);

    beforeEach(() => {
      popovers = [];
      // Mirrors the real helper's contract: mount after 200 ms unless cancelled first.
      handleIssuablePopoverMount.mockImplementation(({ onMount }) => {
        const timer = setTimeout(() => {
          const popover = { $destroy: jest.fn() };
          popovers.push(popover);
          onMount(popover);
        }, 200);
        return () => clearTimeout(timer);
      });
      setHTMLFixture(`
        <div data-testid="root">
          <p>
            See <a data-testid="issue-link" href="${TEST_HOST}/group/project/-/issues/12"><span data-testid="issue-text">the issue</span></a>,
            <a data-testid="relative-link" href="/group/project/-/merge_requests/3">the MR</a>,
            <a data-testid="external-link" href="https://example.com/group/project/-/issues/12">elsewhere</a>,
            and <a data-testid="plain-link" href="${TEST_HOST}/group/project">the project</a>.
          </p>
        </div>
      `);
      dispose = initChatReferencePopovers(findRoot());
    });

    afterEach(() => {
      resetHTMLFixture();
    });

    it('mounts a popover for a reference link hovered through a child element', async () => {
      expect(handleIssuablePopoverMount).not.toHaveBeenCalled();

      await hover(findByTestId('issue-text'));

      expect(handleIssuablePopoverMount).toHaveBeenCalledWith({
        apolloProvider: expect.any(Object),
        target: findIssueLink(),
        innerText: '',
        referenceType: 'issue',
        namespacePath: 'group/project',
        iid: '12',
        cancelOnMouseLeave: false,
        onMount: expect.any(Function),
      });
    });

    it('does not pass the model-written link text as a title', async () => {
      await hover(findByTestId('issue-text'));

      expect(handleIssuablePopoverMount).toHaveBeenCalledWith(
        expect.objectContaining({ innerText: '' }),
      );
      expect(handleIssuablePopoverMount).not.toHaveBeenCalledWith(
        expect.objectContaining({ innerText: 'the issue' }),
      );
    });

    it('resolves a relative href against the current origin', async () => {
      await hover(findByTestId('relative-link'));

      expect(handleIssuablePopoverMount).toHaveBeenCalledWith(
        expect.objectContaining({
          referenceType: 'merge_request',
          namespacePath: 'group/project',
          iid: '3',
        }),
      );
    });

    it.each`
      description               | testId
      ${'a cross-origin link'}  | ${'external-link'}
      ${'a non-reference link'} | ${'plain-link'}
    `('leaves $description alone', async ({ testId }) => {
      await hover(findByTestId(testId));

      expect(handleIssuablePopoverMount).not.toHaveBeenCalled();
    });

    describe('while a mount is pending', () => {
      beforeEach(async () => {
        await hover(findIssueLink());
      });

      it('does not schedule a second mount', async () => {
        await hover(findIssueLink());

        expect(handleIssuablePopoverMount).toHaveBeenCalledTimes(1);
      });
    });

    describe('when the pointer leaves before the popover code loads', () => {
      beforeEach(async () => {
        triggerMouseover(findIssueLink());
        triggerMouseleave(findIssueLink());
        await waitForPromises();
      });

      it('does not start a mount', () => {
        expect(handleIssuablePopoverMount).not.toHaveBeenCalled();
      });
    });

    describe('when the pointer leaves before the popover mounts', () => {
      beforeEach(async () => {
        await hover(findIssueLink());
        triggerMouseleave(findIssueLink());
        waitForMountDelay();
      });

      it('does not mount', () => {
        expect(popovers).toHaveLength(0);
      });

      it('retries on the next hover', async () => {
        await hover(findIssueLink());
        waitForMountDelay();

        expect(popovers).toHaveLength(1);
      });
    });

    describe('when a link receives keyboard focus', () => {
      beforeEach(async () => {
        await focus(findIssueLink());
      });

      it('mounts a popover as hover does', () => {
        waitForMountDelay();

        expect(handleIssuablePopoverMount).toHaveBeenCalledWith(
          expect.objectContaining({ target: findIssueLink(), iid: '12' }),
        );
        expect(popovers).toHaveLength(1);
      });

      it('does not schedule a second mount when hovered as well', async () => {
        await hover(findIssueLink());

        expect(handleIssuablePopoverMount).toHaveBeenCalledTimes(1);
      });

      it('still mounts when the pointer passes over the link', () => {
        triggerMouseenter(findIssueLink());
        triggerMouseleave(findIssueLink());
        waitForMountDelay();

        expect(popovers).toHaveLength(1);
      });

      describe('and focus leaves before the popover mounts', () => {
        beforeEach(() => {
          triggerFocusout(findIssueLink());
          waitForMountDelay();
        });

        it('does not mount', () => {
          expect(popovers).toHaveLength(0);
        });

        it('retries on the next focus', async () => {
          await focus(findIssueLink());
          waitForMountDelay();

          expect(popovers).toHaveLength(1);
        });
      });
    });

    describe('when a hovered link also receives keyboard focus', () => {
      beforeEach(async () => {
        await hover(findIssueLink());
        triggerFocusin(findIssueLink());
        triggerMouseleave(findIssueLink());
      });

      it('still mounts after the pointer leaves', () => {
        waitForMountDelay();

        expect(popovers).toHaveLength(1);
      });

      it('does not mount once focus leaves as well', () => {
        triggerFocusout(findIssueLink());
        waitForMountDelay();

        expect(popovers).toHaveLength(0);
      });
    });

    describe('when the popover has mounted', () => {
      beforeEach(async () => {
        await hover(findIssueLink());
        waitForMountDelay();
        triggerMouseleave(findIssueLink());
      });

      it('mounts once', async () => {
        await hover(findIssueLink());

        expect(handleIssuablePopoverMount).toHaveBeenCalledTimes(1);
      });

      describe('and the href changes', () => {
        beforeEach(async () => {
          findIssueLink().setAttribute('href', `${TEST_HOST}/group/project/-/issues/120`);
          await hover(findIssueLink());
          waitForMountDelay();
        });

        it('mounts a popover for the new href', () => {
          expect(handleIssuablePopoverMount).toHaveBeenLastCalledWith(
            expect.objectContaining({ iid: '120' }),
          );
          expect(popovers).toHaveLength(2);
        });

        it('destroys the stale popover', () => {
          expect(popovers[0].$destroy).toHaveBeenCalledTimes(1);
          expect(popovers[1].$destroy).not.toHaveBeenCalled();
        });
      });
    });

    describe('after dispose', () => {
      beforeEach(async () => {
        dispose();
        await hover(findIssueLink());
        await focus(findIssueLink());
      });

      it('ignores hover and focus', () => {
        expect(handleIssuablePopoverMount).not.toHaveBeenCalled();
      });
    });

    describe('when disposed before the popover code loads', () => {
      beforeEach(async () => {
        triggerMouseover(findIssueLink());
        dispose();
        await waitForPromises();
        waitForMountDelay();
      });

      it('does not start a mount', () => {
        expect(handleIssuablePopoverMount).not.toHaveBeenCalled();
      });
    });

    describe('when disposed while a mount is pending', () => {
      beforeEach(async () => {
        await hover(findIssueLink());
        dispose();
        waitForMountDelay();
      });

      it('cancels the mount', () => {
        expect(popovers).toHaveLength(0);
      });
    });

    describe('when disposed after a popover mounted', () => {
      beforeEach(async () => {
        await hover(findIssueLink());
        waitForMountDelay();
        dispose();
      });

      it('destroys the popover', () => {
        expect(popovers).toHaveLength(1);
        expect(popovers[0].$destroy).toHaveBeenCalledTimes(1);
      });
    });
  });
});
