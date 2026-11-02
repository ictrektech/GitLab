import { GlCollapsibleListbox } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PromptCategories from 'ee/ai/duo_agentic_chat/components/empty_state/prompt_categories.vue';

describe('PromptCategories', () => {
  let wrapper;

  const categories = [
    {
      key: 'agent',
      title: 'Security Analyst',
      contextual: false,
      questions: ['Which vulnerabilities should I fix first?'],
    },
    {
      key: 'merge_request',
      title: '!42',
      contextual: true,
      questions: ['What changed in this diff?'],
    },
    {
      key: 'get_started',
      title: 'Get started',
      contextual: false,
      questions: ['Help me make my CI pipelines run faster', 'What causes pipeline failures?'],
    },
    {
      key: 'development',
      title: 'Development',
      contextual: false,
      questions: ['Show me automated testing strategies'],
    },
    {
      key: 'security',
      title: 'Security',
      contextual: false,
      questions: ['How can I improve my code security?'],
    },
  ];

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(PromptCategories, {
      propsData: {
        categories,
        ...props,
      },
    });
  };

  const findDropdown = () => wrapper.findComponent(GlCollapsibleListbox);
  const findCard = () => wrapper.findByTestId('prompt-category-card');
  const findQuestions = () => wrapper.findAllComponentsByTestId('prompt-category-question');
  const findAnnouncement = () => wrapper.findByTestId('prompt-category-announcement');
  const selectCategory = (key) => findDropdown().vm.$emit('select', key);

  it('lists every category in the dropdown, labelled with the server-supplied title', () => {
    createComponent();

    expect(findDropdown().props('items')).toEqual([
      { value: 'agent', text: 'Security Analyst', icon: 'agent-ai' },
      { value: 'merge_request', text: '!42', icon: 'merge-request' },
      { value: 'get_started', text: 'Get started', icon: 'tanuki-ai' },
      { value: 'development', text: 'Development', icon: 'code' },
      { value: 'security', text: 'Security', icon: 'shield' },
    ]);
  });

  it('falls back to a generic icon for a key it has no icon for', () => {
    createComponent({
      categories: [
        { key: 'unknown', title: 'This page', contextual: true, questions: ['What is this?'] },
      ],
    });

    expect(findDropdown().props('items')).toEqual([
      { value: 'unknown', text: 'This page', icon: 'documents' },
    ]);
  });

  it('heads the section with a subtle heading', () => {
    createComponent();

    expect(wrapper.find('h3').text()).toBe('Suggestions');
  });

  describe('with no category selected', () => {
    beforeEach(() => {
      createComponent();
    });

    it('prompts the user to pick one', () => {
      expect(findDropdown().props()).toMatchObject({
        toggleText: 'Select category',
        icon: '',
        selected: null,
      });
    });

    it('renders no card', () => {
      expect(findCard().exists()).toBe(false);
    });

    it('announces nothing', () => {
      expect(findAnnouncement().text()).toBe('');
    });
  });

  describe('with an initial expanded key', () => {
    beforeEach(() => {
      createComponent({ initialExpandedKey: 'get_started' });
    });

    it('shows that category as the dropdown selection', () => {
      expect(findDropdown().props()).toMatchObject({
        toggleText: 'Get started',
        icon: 'tanuki-ai',
        selected: 'get_started',
      });
    });

    it('renders its questions as a list named after the category', () => {
      expect(findCard().attributes('aria-label')).toBe('Suggestions for Get started');
      expect(findQuestions().wrappers.map((question) => question.text())).toEqual([
        'Help me make my CI pipelines run faster',
        'What causes pipeline failures?',
      ]);
    });

    it('swaps the card when the user picks another category', async () => {
      await selectCategory('security');

      expect(findDropdown().props('toggleText')).toBe('Security');
      expect(findQuestions().at(0).text()).toBe('How can I improve my code security?');
    });

    // Focus returns to the dropdown toggle on select, so the swap is only
    // conveyed by the live region.
    it('announces the swapped-in category', async () => {
      await selectCategory('security');

      expect(findAnnouncement().text()).toBe('1 suggestion for Security');
    });
  });

  describe('selecting a category', () => {
    beforeEach(async () => {
      createComponent();
      await selectCategory('development');
    });

    it('shows its questions', () => {
      expect(findDropdown().props('toggleText')).toBe('Development');
      expect(findQuestions().at(0).text()).toBe('Show me automated testing strategies');
    });

    it('announces the selection', () => {
      expect(findAnnouncement().text()).toBe('1 suggestion for Development');
    });

    it('emits select with the question when a prompt is clicked', async () => {
      await findQuestions().at(0).vm.$emit('click');

      expect(wrapper.emitted('select')).toEqual([['Show me automated testing strategies']]);
    });
  });

  // Switching agent replaces the category list, which can drop the agent
  // category the user was looking at.
  describe('when the selected category leaves the list', () => {
    const remainingCategories = categories.filter((category) => category.key !== 'agent');

    beforeEach(async () => {
      createComponent({ initialExpandedKey: 'get_started' });
      await selectCategory('agent');
      await wrapper.setProps({ categories: remainingCategories });
    });

    it('falls back to the initial expanded category', () => {
      expect(findDropdown().props()).toMatchObject({
        toggleText: 'Get started',
        selected: 'get_started',
      });
      expect(findQuestions().at(0).text()).toBe('Help me make my CI pipelines run faster');
    });
  });
});
