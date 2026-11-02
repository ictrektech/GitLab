import { defaultClient } from 'ee/roadmap/graphql';
import groupMilestonesQuery from 'ee/roadmap/queries/group_milestones.query.graphql';
import {
  createMockGroupMilestonesQueryResponse,
  mockGroupMilestonesQueryResponsePage1,
  mockGroupMilestonesQueryResponsePage2,
  mockSubgroupMilestoneNode,
} from 'ee_jest/roadmap/mock_data';

describe('roadmap cache policy for group milestones', () => {
  const variables = {
    fullPath: 'gitlab-org',
    state: 'active',
    timeframe: { start: '2018-01-01', end: '2018-12-31' },
    includeDescendants: true,
    includeAncestors: true,
    first: 100,
  };
  const otherTimeframeVariables = {
    ...variables,
    timeframe: { start: '2019-01-01', end: '2019-12-31' },
  };

  const writePage = (pageVariables, { data }) => {
    defaultClient.writeQuery({ query: groupMilestonesQuery, variables: pageVariables, data });
  };

  const readNodes = (readVariables) =>
    defaultClient.readQuery({ query: groupMilestonesQuery, variables: readVariables }).group
      .milestones.nodes;

  const readTitles = (readVariables) => readNodes(readVariables).map(({ title }) => title);

  afterEach(async () => {
    await defaultClient.clearStore();
  });

  it('merges the pages of one timeframe into one list', () => {
    writePage(variables, mockGroupMilestonesQueryResponsePage1);
    writePage(
      { ...variables, after: 'milestones-page-1-end' },
      mockGroupMilestonesQueryResponsePage2,
    );

    expect(readTitles(variables)).toEqual([
      'Sprint - Tempore voluptatibus et aut consequatur similique animi dolores veritatis.',
      'Milestone 2',
      mockSubgroupMilestoneNode.title,
    ]);
  });

  it('adds a milestone already in the list once, by its id', () => {
    const page2Variables = { ...variables, after: 'milestones-page-1-end' };
    const sameTitleNode = { ...mockSubgroupMilestoneNode, id: 'gid://gitlab/Milestone/43' };

    writePage(variables, mockGroupMilestonesQueryResponsePage1);
    writePage(page2Variables, mockGroupMilestonesQueryResponsePage2);
    writePage(page2Variables, mockGroupMilestonesQueryResponsePage2);
    writePage(
      { ...variables, after: 'milestones-page-2-end' },
      createMockGroupMilestonesQueryResponse([sameTitleNode]),
    );

    expect(readNodes(variables).map(({ id }) => id)).toEqual([
      'gid://gitlab/Milestone/40',
      'gid://gitlab/Milestone/41',
      mockSubgroupMilestoneNode.id,
      sameTitleNode.id,
    ]);
  });

  it('keeps the pages of another timeframe in a list of their own', () => {
    writePage(variables, mockGroupMilestonesQueryResponsePage1);
    writePage(otherTimeframeVariables, mockGroupMilestonesQueryResponsePage2);

    expect(readTitles(variables)).toEqual([
      'Sprint - Tempore voluptatibus et aut consequatur similique animi dolores veritatis.',
      'Milestone 2',
    ]);
    expect(readTitles(otherTimeframeVariables)).toEqual([mockSubgroupMilestoneNode.title]);
  });
});
