import { workItemTypesStatusNameOptions } from 'ee/ai/duo_agents_platform/utils/work_item_statuses';

describe('workItemTypesStatusNameOptions', () => {
  const statusWidget = (statuses) => ({
    type: 'STATUS',
    allowedStatuses: statuses.map(([id, name]) => ({
      id: `gid://gitlab/WorkItems::Statuses::Custom::Status/${id}`,
      name,
      category: 'in_progress',
    })),
  });
  const workItemTypes = [
    {
      id: 'gid://gitlab/WorkItems::Type/1',
      name: 'Issue',
      widgetDefinitions: [statusWidget([[1, 'In review']])],
    },
    {
      id: 'gid://gitlab/WorkItems::Type/5',
      name: 'Task',
      widgetDefinitions: [
        statusWidget([
          [2, 'In dev'],
          [3, 'In review'],
        ]),
      ],
    },
  ];

  it('lists the statuses of every type when no type is selected', () => {
    expect(workItemTypesStatusNameOptions(workItemTypes, [])).toEqual([
      { value: 'In review', text: 'In review' },
      { value: 'In dev', text: 'In dev' },
    ]);
  });

  it('lists only the statuses of the selected types', () => {
    expect(workItemTypesStatusNameOptions(workItemTypes, [1])).toEqual([
      { value: 'In review', text: 'In review' },
    ]);
  });
});
