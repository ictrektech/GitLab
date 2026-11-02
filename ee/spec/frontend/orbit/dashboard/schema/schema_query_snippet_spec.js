import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import SchemaQuerySnippet from 'ee/orbit/dashboard/schema/schema_query_snippet.vue';

describe('SchemaQuerySnippet', () => {
  let wrapper;
  const query = 'MATCH (u:User)\nWHERE u.id IS NOT NULL\nRETURN u.username\nLIMIT 25';

  const createComponent = () => {
    wrapper = shallowMountExtended(SchemaQuerySnippet, { propsData: { query } });
  };

  beforeEach(() => {
    createComponent();
  });

  it('shows the query and copies it', () => {
    expect(wrapper.findByTestId('schema-query-text').text()).toBe(query);
    expect(wrapper.findComponent(ClipboardButton).props('text')).toBe(query);
  });

  describe('when the user opens the query', () => {
    beforeEach(() => {
      wrapper.findComponent(GlButton).vm.$emit('click');
    });

    it('emits the query', () => {
      expect(wrapper.emitted('open-query')).toEqual([[query]]);
    });
  });
});
