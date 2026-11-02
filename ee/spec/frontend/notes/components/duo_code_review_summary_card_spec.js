import { GlIcon, GlLink } from '@gitlab/ui';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import Vue, { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { useDiscussions } from '~/notes/store/discussions';
import DuoCodeReviewSummaryCard from 'ee/notes/components/duo_code_review_summary_card.vue';

Vue.use(PiniaVuePlugin);

describe('DuoCodeReviewSummaryCard', () => {
  let wrapper;
  let pinia;

  const findingDiscussion = ({ noteId, path, line, severity, resolved = false }) => ({
    id: `discussion-${noteId}`,
    resolved,
    position: { new_path: path, new_line: line },
    notes: [
      {
        id: noteId,
        duo_code_review_finding: { severity, category: 'missing_test', depth: 'deep' },
      },
    ],
  });

  const createComponent = ({ findingNoteIds = ['1', '2', '3'], depth = 'deep' } = {}) => {
    wrapper = mountExtended(DuoCodeReviewSummaryCard, {
      pinia,
      propsData: { noteId: '99', findingNoteIds, depth },
    });
  };

  const findCard = () => wrapper.findByTestId('duo-code-review-summary-card');
  const findToggle = () => wrapper.findByTestId('duo-code-review-summary-toggle');
  const findDepthBadge = () => wrapper.findByTestId('duo-code-review-depth-badge');
  const findGroups = () => wrapper.findAllByTestId('duo-code-review-summary-group');
  const findFindings = () => wrapper.findAllByTestId('duo-code-review-summary-finding');

  beforeEach(() => {
    pinia = createTestingPinia({ stubActions: false });
    useDiscussions().discussions = [
      findingDiscussion({ noteId: '1', path: 'b.rb', line: 4, severity: 'minor' }),
      findingDiscussion({
        noteId: '2',
        path: 'a.rb',
        line: 9,
        severity: 'critical',
        resolved: true,
      }),
      findingDiscussion({ noteId: '3', path: 'a.rb', line: 2, severity: 'minor' }),
      findingDiscussion({ noteId: '4', path: 'c.rb', line: 1, severity: 'major' }),
      { id: 'human', notes: [{ id: '5' }] },
    ];
  });

  describe('with findings from this review', () => {
    beforeEach(() => {
      createComponent();
    });

    it('counts only this review findings, their files and resolved threads', () => {
      expect(findToggle().text()).toMatchInterpolatedText(
        '3 findings across 2 files · 1 resolved Deep review',
      );
    });

    it('shows the review depth', () => {
      expect(findDepthBadge().text()).toBe('Deep review');
    });

    it('does not show a depth badge without a review depth', () => {
      createComponent({ depth: null });

      expect(findDepthBadge().exists()).toBe(false);
    });

    it('starts collapsed', () => {
      expect(findToggle().attributes('aria-expanded')).toBe('false');
    });

    it('groups findings by severity, ordered by file and line', async () => {
      await findToggle().trigger('click');

      expect(findToggle().attributes('aria-expanded')).toBe('true');
      expect(findGroups().wrappers.map((group) => group.find('h4').text())).toEqual([
        'Critical',
        'Minor',
      ]);
      expect(
        findFindings().wrappers.map((finding) => [
          finding.findComponent(GlLink).text(),
          finding.find('[data-testid="duo-code-review-summary-location"]').text(),
        ]),
      ).toEqual([
        ['Missing test', 'a.rb:9'],
        ['Missing test', 'a.rb:2'],
        ['Missing test', 'b.rb:4'],
      ]);
    });

    it('links each finding to its thread and shows whether it is resolved', () => {
      const [resolved, unresolved] = findFindings().wrappers;

      expect(resolved.findComponent(GlLink).attributes('href')).toBe('#note_2');
      expect(resolved.findComponent(GlIcon).props('name')).toBe('check-circle-filled');
      expect(unresolved.findComponent(GlIcon).props('name')).toBe('check-circle');
    });

    it('updates when a thread is resolved', async () => {
      useDiscussions().discussions[0].resolved = true;
      await nextTick();

      expect(findToggle().text()).toMatchInterpolatedText(
        '3 findings across 2 files · 2 resolved Deep review',
      );
    });
  });

  it('leaves out the resolved count when nothing is resolved', () => {
    createComponent({ findingNoteIds: ['1', '3'] });

    expect(findToggle().text()).toMatchInterpolatedText('2 findings across 2 files Deep review');
  });

  it('does not render when none of the review findings are loaded', () => {
    createComponent({ findingNoteIds: ['42'] });

    expect(findCard().exists()).toBe(false);
  });
});
