import { GlAccordionItem, GlLink } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ClipboardButton from '~/vue_shared/components/clipboard_button.vue';
import QueryGqlSyntax from 'ee/orbit/dashboard/query_editor/query_gql_syntax.vue';

describe('QueryGqlSyntax', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = mountExtended(QueryGqlSyntax);
  };

  const codeTexts = (container) => container.findAll('code').wrappers.map((code) => code.text());
  const findStarter = () => wrapper.findByTestId('gql-starter');
  const findMoreSyntax = () => wrapper.findComponent(GlAccordionItem);

  beforeEach(() => {
    createComponent();
  });

  it('shows the seven starter clauses with an example and a sentence each', () => {
    expect(codeTexts(findStarter())).toEqual([
      'MATCH (u:User)-[:AUTHORED]->(mr:MergeRequest)',
      "WHERE mr.state = 'merged'",
      'RETURN u.username, mr.title',
      'RETURN u.username, count(mr) AS merged',
      'ORDER BY mr.merged_at DESC',
      'SKIP 25',
      'LIMIT 25',
    ]);
    expect(findStarter().find('li').text()).toContain('Find entities and how they connect.');
  });

  it('copies the example of each starter clause', () => {
    expect(
      findStarter()
        .findAllComponents(ClipboardButton)
        .wrappers.map((button) => button.props('text')),
    ).toEqual(codeTexts(findStarter()));
  });

  it('folds the rest of the syntax under More syntax, in three groups', () => {
    expect(findMoreSyntax().props('title')).toBe('More syntax');
    expect(
      findMoreSyntax()
        .findAll('h4')
        .wrappers.map((heading) => heading.text()),
    ).toEqual(['Patterns', 'Filters', 'Columns']);
    expect(codeTexts(findMoreSyntax())).toHaveLength(11);
    expect(codeTexts(findMoreSyntax())).toContain(
      "(g:Group {full_path: 'gitlab-org'})-[:CONTAINS*1..3]->(s:Group)",
    );
  });

  it('ends with the limits and links to the full reference and openCypher', () => {
    expect(wrapper.find('footer').text()).toContain(
      'Read-only. No OR or OPTIONAL MATCH. Up to 3 hops and 1,000 rows.',
    );
    expect(
      wrapper
        .findAllComponents(GlLink)
        .wrappers.map((link) => [link.text(), link.attributes('href')]),
    ).toEqual([
      ['Full GQL reference', 'https://docs.gitlab.com/orbit/remote/queries/query-language/'],
      ['openCypher 9', 'https://opencypher.org/resources/'],
    ]);
  });
});
