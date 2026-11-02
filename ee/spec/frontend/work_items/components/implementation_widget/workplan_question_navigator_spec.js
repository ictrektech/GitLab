import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import WorkplanQuestionNavigator from 'ee/work_items/components/implementation_widget/workplan_question_navigator.vue';
import { jumpToQuestion } from 'ee/work_items/utils/question_navigation';

jest.mock('ee/work_items/utils/question_navigation');

describe('WorkplanQuestionNavigator', () => {
  let wrapper;

  const questions = [
    { noteId: 'gid://gitlab/DiscussionNote/1', answered: false },
    { noteId: 'gid://gitlab/DiscussionNote/2', answered: true },
    { noteId: 'gid://gitlab/DiscussionNote/3', answered: false },
  ];

  const createComponent = () => {
    wrapper = shallowMountExtended(WorkplanQuestionNavigator, {
      propsData: { questions },
    });
  };

  const findPreviousButton = () => wrapper.findComponentByTestId('previous-question-button');
  const findNextButton = () => wrapper.findComponentByTestId('next-question-button');

  beforeEach(() => {
    createComponent();
  });

  it.each`
    scenario      | findButton            | label                       | icon                 | direction
    ${'previous'} | ${findPreviousButton} | ${'Previous open question'} | ${'chevron-lg-up'}   | ${'previous'}
    ${'next'}     | ${findNextButton}     | ${'Next open question'}     | ${'chevron-lg-down'} | ${'next'}
  `(
    'jumps between the unanswered questions from the $scenario button',
    ({ findButton, label, icon, direction }) => {
      expect(findButton().attributes('aria-label')).toBe(label);
      expect(findButton().props('icon')).toBe(icon);

      findButton().vm.$emit('click');

      expect(jumpToQuestion).toHaveBeenCalledWith({
        noteIds: ['gid://gitlab/DiscussionNote/1', 'gid://gitlab/DiscussionNote/3'],
        direction,
      });
    },
  );
});
