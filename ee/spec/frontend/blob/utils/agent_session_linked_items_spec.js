import { buildLinkedItems, pickShownLinkedItems } from 'ee/blob/utils/agent_session_linked_items';

describe('agent session linked items', () => {
  describe('buildLinkedItems', () => {
    it('lists work items, merge requests, notes and pipelines in that order', () => {
      const details = {
        pipelineLinks: {
          nodes: [
            { linkType: 'SOURCE', pipeline: { id: 'gid://gitlab/Ci::Pipeline/7', path: '/p/7' } },
          ],
        },
        noteLinks: {
          nodes: [
            {
              linkType: 'TRIGGERED',
              note: { url: '/note/1', discussion: { noteable: { reference: '!3' } } },
            },
          ],
        },
        mergeRequestLinks: {
          nodes: [{ linkType: 'CREATED', mergeRequest: { iid: '3', webPath: '/mr/3' } }],
        },
        workItemLinks: {
          nodes: [{ linkType: 'SOURCE', workItem: { iid: '5', webPath: '/i/5' } }],
        },
      };

      expect(buildLinkedItems(details)).toEqual([
        {
          linkType: 'SOURCE',
          kind: 'workItem',
          icon: 'work-item-issue',
          reference: '#5',
          href: '/i/5',
        },
        {
          linkType: 'CREATED',
          kind: 'mergeRequest',
          icon: 'merge-request',
          reference: '!3',
          href: '/mr/3',
        },
        { linkType: 'TRIGGERED', kind: 'note', icon: 'comment', reference: '!3', href: '/note/1' },
        { linkType: 'SOURCE', kind: 'pipeline', icon: 'pipeline', reference: '#7', href: '/p/7' },
      ]);
    });

    it('skips linked items the user cannot read', () => {
      const details = {
        workItemLinks: { nodes: [{ linkType: 'SOURCE', workItem: null }] },
        mergeRequestLinks: { nodes: [{ linkType: 'CREATED', mergeRequest: null }] },
        noteLinks: { nodes: [{ linkType: 'CREATED', note: null }] },
        pipelineLinks: { nodes: [{ linkType: 'SOURCE', pipeline: null }] },
      };

      expect(buildLinkedItems(details)).toEqual([]);
    });
  });

  describe('pickShownLinkedItems', () => {
    const item = (linkType, href) => ({ linkType, href });

    it.each`
      description                                       | items                                                                                         | shown
      ${'the first source and first created item'}      | ${[item('CREATED', 'c1'), item('SOURCE', 's1'), item('SOURCE', 's2'), item('CREATED', 'c2')]} | ${['s1', 'c1']}
      ${'the first two items when nothing was created'} | ${[item('SOURCE', 's1'), item('TRIGGERED', 's2'), item('SOURCE', 's3')]}                      | ${['s1', 's2']}
      ${'the first two items when nothing is a source'} | ${[item('CREATED', 'c1'), item('CREATED', 'c2'), item('CREATED', 'c3')]}                      | ${['c1', 'c2']}
      ${'nothing when there are no items'}              | ${[]}                                                                                         | ${[]}
    `('shows $description', ({ items, shown }) => {
      expect(pickShownLinkedItems(items).map(({ href }) => href)).toEqual(shown);
    });
  });
});
