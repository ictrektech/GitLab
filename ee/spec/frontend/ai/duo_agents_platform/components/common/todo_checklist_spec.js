import { GlIcon, GlLoadingIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import TodoChecklist from 'ee/ai/duo_agents_platform/components/common/todo_checklist.vue';

describe('TodoChecklist', () => {
  let wrapper;

  const findContainer = () => wrapper.findByTestId('todo-checklist-container');
  const findAllItems = () => wrapper.findAll('li');
  const findIcon = (index) => findAllItems().at(index).findComponent(GlIcon);
  const findDescription = (index) => wrapper.findAllByTestId('todo-description').at(index);
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);

  const createWrapper = (toolInfo = {}, props = {}) => {
    wrapper = shallowMountExtended(TodoChecklist, {
      propsData: { toolInfo, ...props },
    });
  };

  const mockTodos = [
    { status: 'completed', description: 'Set up repository' },
    { status: 'in_progress', description: 'Write tests' },
    { status: 'pending', description: 'Deploy to staging' },
    { status: 'cancelled', description: 'Old task' },
    { status: 'unknown_status', description: 'Mystery task' },
  ];

  describe('when todos are present', () => {
    beforeEach(() => {
      createWrapper({ args: { todos: mockTodos } });
    });

    it('renders correct number of list items', () => {
      expect(findAllItems()).toHaveLength(mockTodos.length);
    });

    it.each`
      status              | index | name                  | variant      | ariaLabel
      ${'completed'}      | ${0}  | ${'status-success'}   | ${'success'} | ${'Completed'}
      ${'pending'}        | ${2}  | ${'status-waiting'}   | ${'subtle'}  | ${'Pending'}
      ${'cancelled'}      | ${3}  | ${'status-cancelled'} | ${'subtle'}  | ${'Canceled'}
      ${'unknown_status'} | ${4}  | ${'status-waiting'}   | ${'subtle'}  | ${'Pending'}
    `('renders a labelled $name icon for $status todos', ({ index, name, variant, ariaLabel }) => {
      expect(findIcon(index).props()).toMatchObject({ name, variant, ariaLabel, size: 12 });
    });

    it('renders a labelled loading icon for in_progress todos', () => {
      expect(findLoadingIcon().props('label')).toBe('In progress');
    });

    it('shrinks the loading icon to match the 12px status icons', () => {
      expect(findLoadingIcon().classes()).toContain('todo-checklist-spinner');
    });

    it('strikes through and de-emphasizes only cancelled todos', () => {
      expect(findDescription(3).classes()).toEqual(
        expect.arrayContaining(['gl-line-through', 'gl-text-subtle']),
      );

      [0, 1, 2, 4].forEach((index) => {
        expect(findDescription(index).classes()).not.toContain('gl-line-through');
        expect(findDescription(index).classes()).not.toContain('gl-text-subtle');
      });
    });

    it('renders description text for each todo', () => {
      mockTodos.forEach((todo, index) => {
        expect(findAllItems().at(index).text()).toContain(todo.description);
      });
    });
  });

  describe('bordered prop', () => {
    describe('when bordered is true (default)', () => {
      beforeEach(() => {
        createWrapper({ args: { todos: mockTodos } });
      });

      it('applies border classes', () => {
        expect(findContainer().classes()).toContain('gl-border');
      });
    });

    describe('when bordered is false', () => {
      beforeEach(() => {
        createWrapper({ args: { todos: mockTodos } }, { bordered: false });
      });

      it('does not apply border classes', () => {
        expect(findContainer().classes()).not.toContain('gl-border');
      });
    });
  });

  describe('flowFinished prop', () => {
    const inProgressTodos = [{ status: 'in_progress', description: 'Write tests' }];

    describe('when flowFinished is false (default)', () => {
      beforeEach(() => {
        createWrapper({ args: { todos: inProgressTodos } });
      });

      it('renders the loading icon for an in_progress todo', () => {
        expect(findLoadingIcon().exists()).toBe(true);
      });
    });

    describe('when flowFinished is true', () => {
      beforeEach(() => {
        createWrapper({ args: { todos: inProgressTodos } }, { flowFinished: true });
      });

      it('does not render the loading icon for an in_progress todo', () => {
        expect(findLoadingIcon().exists()).toBe(false);
      });

      it('renders the pending icon instead', () => {
        expect(findIcon(0).props()).toMatchObject({ name: 'status-waiting', ariaLabel: 'Pending' });
      });
    });
  });

  describe('when todos array is empty', () => {
    it('renders nothing', () => {
      createWrapper({ args: { todos: [] } });
      expect(findContainer().exists()).toBe(false);
    });
  });

  describe('when args is missing', () => {
    it('handles missing args gracefully (renders nothing)', () => {
      createWrapper({});
      expect(findContainer().exists()).toBe(false);
    });
  });

  describe('when args.todos is missing', () => {
    it('handles missing args.todos gracefully (renders nothing)', () => {
      createWrapper({ args: {} });
      expect(findContainer().exists()).toBe(false);
    });
  });
});
