import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SectionHeading from 'ee/security_orchestration/components/policy_editor/dependency_firewall/components/section_heading.vue';

describe('SectionHeading', () => {
  let wrapper;

  const createWrapper = (propsData) => {
    wrapper = shallowMountExtended(SectionHeading, { propsData });
  };

  const findSubtitle = () => wrapper.find('p');

  it('renders the title', () => {
    createWrapper({ title: 'What should it look for?' });

    expect(wrapper.find('h4').text()).toBe('What should it look for?');
  });

  it('renders the subtitle when provided', () => {
    createWrapper({
      title: 'What should it look for?',
      subtitle: 'Three kinds of rule, all in one policy.',
    });

    expect(findSubtitle().text()).toBe('Three kinds of rule, all in one policy.');
  });

  it('does not render a subtitle when not provided', () => {
    createWrapper({ title: 'What should it look for?' });

    expect(findSubtitle().exists()).toBe(false);
  });
});
