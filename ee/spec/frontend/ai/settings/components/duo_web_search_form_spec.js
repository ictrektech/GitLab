import { shallowMount } from '@vue/test-utils';
import { GlFormCheckbox, GlFormGroup, GlLink, GlSprintf } from '@gitlab/ui';
import DuoWebSearchForm from 'ee/ai/settings/components/duo_web_search_form.vue';

describe('DuoWebSearchForm', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMount(DuoWebSearchForm, {
      propsData: {
        webSearchEnabled: false,
        ...props,
      },
      stubs: {
        GlFormCheckbox,
        GlFormGroup,
        GlSprintf,
      },
    });
  };

  const findFormGroup = () => wrapper.findComponent(GlFormGroup);
  const findCheckbox = () => wrapper.findComponent(GlFormCheckbox);
  const findCheckboxLabel = () => findCheckbox().find('span');
  const findHelpLink = () => wrapper.findComponent(GlLink);

  beforeEach(() => {
    createComponent();
  });

  it('renders the section title', () => {
    expect(findFormGroup().attributes('label')).toBe('Web search');
  });

  it('renders the checkbox label', () => {
    expect(findCheckboxLabel().text()).toBe('Allow web search');
  });

  it('renders the help text', () => {
    expect(findCheckbox().text()).toContain(
      'Make web search available in GitLab Duo Chat for this group and its subgroups and projects. Users can then turn it on in a conversation. Learn more about web search.',
    );
  });

  it('links the help text to the web search docs', () => {
    expect(findHelpLink().text()).toBe('Learn more about web search');
    expect(findHelpLink().attributes('href')).toBe(
      '/help/user/gitlab_duo_chat/agentic_chat#allow-web-search-for-a-group',
    );
    expect(findHelpLink().attributes('target')).toBe('_blank');
  });

  it('exposes the checkbox under a stable test id', () => {
    expect(wrapper.find('[data-testid="web-search-enabled-checkbox"]').exists()).toBe(true);
  });

  it('names the checkbox after the attribute the settings API expects', () => {
    expect(findCheckbox().props('name')).toBe(
      'namespace[ai_settings_attributes][web_search_enabled]',
    );
  });

  it.each`
    webSearchEnabled | description
    ${true}          | ${'checked'}
    ${false}         | ${'unchecked'}
  `(
    'renders the checkbox as $description when webSearchEnabled is $webSearchEnabled',
    ({ webSearchEnabled }) => {
      createComponent({ props: { webSearchEnabled } });

      expect(findCheckbox().props('checked')).toBe(webSearchEnabled);
    },
  );

  it.each([[true], [false]])('sets the checkbox disabled state to %p', (disabledCheckbox) => {
    createComponent({ props: { disabledCheckbox } });

    expect(findCheckbox().props('disabled')).toBe(disabledCheckbox);
  });

  it.each([[true], [false]])('emits change with %p when the checkbox is toggled', (value) => {
    findCheckbox().vm.$emit('change', value);

    expect(wrapper.emitted('change')).toEqual([[value]]);
  });
});
