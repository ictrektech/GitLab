import { isGroupExpanded, toggleExpandedGroup, withExpandedChildren } from 'ee/geo_sites/utils';

describe('Geo Sites utils', () => {
  describe('isGroupExpanded', () => {
    it.each([
      [['uploads'], true],
      [['other'], false],
      [[], false],
    ])('with expanded groups %j returns %s', (expandedGroups, expected) => {
      expect(isGroupExpanded(expandedGroups, { namePlural: 'uploads' })).toBe(expected);
    });
  });

  describe('toggleExpandedGroup', () => {
    it('adds a collapsed group', () => {
      expect(toggleExpandedGroup(['other'], { namePlural: 'uploads' })).toStrictEqual([
        'other',
        'uploads',
      ]);
    });

    it('removes an expanded group', () => {
      expect(toggleExpandedGroup(['other', 'uploads'], { namePlural: 'uploads' })).toStrictEqual([
        'other',
      ]);
    });
  });

  describe('withExpandedChildren', () => {
    const flat = { namePlural: 'repositories' };
    const group = { namePlural: 'uploads', children: [{ namePlural: 'group_uploads' }] };

    it('keeps a group collapsed when it is not expanded', () => {
      expect(withExpandedChildren([group, flat], [])).toStrictEqual([group, flat]);
    });

    it('inserts the children of an expanded group after it, marked as child rows', () => {
      expect(withExpandedChildren([group, flat], ['uploads'])).toStrictEqual([
        group,
        { namePlural: 'group_uploads', isChild: true },
        flat,
      ]);
    });
  });
});
