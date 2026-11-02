import { GlAccordion, GlAccordionItem } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { makeMockUserCalloutDismisser } from 'helpers/mock_user_callout_dismisser';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import waitForPromises from 'helpers/wait_for_promises';
import deleteUserCalloutMutation from '~/graphql_shared/mutations/delete_user_callout.mutation.graphql';
import UseGitlabLocallyWidget from '~/homepage/components/use_gitlab_locally_widget.vue';
import { logError } from '~/lib/logger';
import * as Sentry from '~/sentry/sentry_browser_wrapper';

Vue.use(VueApollo);

jest.mock('~/lib/logger');
jest.mock('~/sentry/sentry_browser_wrapper');

const deleteUserCalloutResponse = (errors = []) => ({
  data: {
    userCalloutDelete: {
      errors,
      userCallout: { featureName: 'USE_GITLAB_LOCALLY_HOMEPAGE_WIDGET' },
    },
  },
});

describe('UseGitlabLocallyWidget', () => {
  let wrapper;
  let userCalloutDismissSpy;
  let deleteUserCalloutHandler;
  let mockToastShow;
  let mockToastHide;

  const findWidget = () => wrapper.findByTestId('homepage-use-gitlab-locally-widget');
  const findRemoveButton = () => wrapper.findComponentByTestId('remove-button');
  const findAccordion = () => wrapper.findComponent(GlAccordion);
  const findAccordionItems = () => wrapper.findAllComponents(GlAccordionItem);
  const findLink = (id) => wrapper.findComponentByTestId(`link-${id}`);
  const lastToastOptions = () => mockToastShow.mock.calls.at(-1)[1];

  const createComponent = () => {
    userCalloutDismissSpy = jest.fn().mockResolvedValue();
    deleteUserCalloutHandler = jest.fn().mockResolvedValue(deleteUserCalloutResponse());
    mockToastShow = jest.fn();
    mockToastHide = jest.fn();

    wrapper = mountExtended(UseGitlabLocallyWidget, {
      apolloProvider: createMockApollo([[deleteUserCalloutMutation, deleteUserCalloutHandler]]),
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
      stubs: {
        UserCalloutDismisser: makeMockUserCalloutDismisser({
          dismiss: userCalloutDismissSpy,
        }),
      },
      mocks: {
        $toast: { show: mockToastShow },
      },
    });
  };

  const clickRemove = async () => {
    findRemoveButton().vm.$emit('click');
    await nextTick();
  };

  beforeEach(() => {
    createComponent();
  });

  it('renders the widget title', () => {
    expect(wrapper.findByRole('heading', { name: 'Use GitLab locally' }).exists()).toBe(true);
  });

  it('renders the accordion with level 3 headers', () => {
    expect(findAccordion().props('headerLevel')).toBe(3);
  });

  it('renders an accordion item for each suggestion', () => {
    expect(findAccordionItems().wrappers.map((item) => item.props('title'))).toEqual([
      'Install a GitLab extension in your IDE',
      'Install the GitLab CLI',
    ]);
  });

  it('renders the suggestion descriptions', () => {
    expect(findAccordionItems().at(0).text()).toContain(
      'Manage your projects and use GitLab Duo directly in your editor.',
    );
    expect(findAccordionItems().at(1).text()).toContain(
      'Manage your projects and use GitLab Duo in your terminal.',
    );
  });

  it.each`
    id              | text            | href
    ${'vs_code'}    | ${'VS Code'}    | ${'/help/editor_extensions/visual_studio_code/setup.md'}
    ${'jetbrains'}  | ${'JetBrains'}  | ${'/help/editor_extensions/jetbrains_ide/setup.md'}
    ${'gitlab_cli'} | ${'GitLab CLI'} | ${'https://gitlab.com/gitlab-org/cli#installation'}
  `('renders the $text link opening in a new tab', ({ id, text, href }) => {
    const link = findLink(id);

    expect(link.text()).toBe(text);
    expect(link.props()).toMatchObject({ href, target: '_blank', showExternalIcon: true });
  });

  it('renders the remove button with a tooltip', () => {
    expect(findRemoveButton().attributes()).toMatchObject({
      title: 'Remove',
      'aria-label': 'Remove Use GitLab locally widget',
    });
    expect(getBinding(findRemoveButton().element, 'gl-tooltip')).toBeDefined();
  });

  describe('when the remove button is clicked', () => {
    beforeEach(async () => {
      await clickRemove();
    });

    it('hides the widget', () => {
      expect(findWidget().exists()).toBe(false);
    });

    it('dismisses the callout', () => {
      expect(userCalloutDismissSpy).toHaveBeenCalledTimes(1);
    });

    it('shows a toast with an Undo action', () => {
      expect(mockToastShow).toHaveBeenCalledWith(
        'Use GitLab locally widget was removed.',
        expect.objectContaining({ action: expect.objectContaining({ text: 'Undo' }) }),
      );
    });

    it('does not delete the callout', () => {
      expect(deleteUserCalloutHandler).not.toHaveBeenCalled();
    });
  });

  describe('when Undo is clicked', () => {
    const clickUndo = async () => {
      await clickRemove();
      lastToastOptions().action.onClick(null, { hide: mockToastHide });
      await waitForPromises();
    };

    describe('when the callout is deleted', () => {
      beforeEach(async () => {
        await clickUndo();
      });

      it('shows the widget again', () => {
        expect(findWidget().exists()).toBe(true);
      });

      it('hides the toast', () => {
        expect(mockToastHide).toHaveBeenCalled();
      });

      it('deletes the callout', () => {
        expect(deleteUserCalloutHandler).toHaveBeenCalledWith({
          input: { featureName: 'use_gitlab_locally_homepage_widget' },
        });
      });

      it('does not report an error', () => {
        expect(Sentry.captureException).not.toHaveBeenCalled();
      });
    });

    it('waits for the dismissal to be saved before deleting the callout', async () => {
      let resolveDismissal;
      userCalloutDismissSpy.mockReturnValue(
        new Promise((resolve) => {
          resolveDismissal = resolve;
        }),
      );

      await clickRemove();
      lastToastOptions().action.onClick(null, { hide: mockToastHide });
      await waitForPromises();

      expect(deleteUserCalloutHandler).not.toHaveBeenCalled();

      resolveDismissal();
      await waitForPromises();

      expect(deleteUserCalloutHandler).toHaveBeenCalledTimes(1);
    });

    it('waits for the callout to be deleted before dismissing it again', async () => {
      let resolveDelete;
      deleteUserCalloutHandler.mockReturnValue(
        new Promise((resolve) => {
          resolveDelete = resolve;
        }),
      );

      await clickUndo();
      await clickRemove();
      await waitForPromises();

      expect(userCalloutDismissSpy).toHaveBeenCalledTimes(1);

      resolveDelete(deleteUserCalloutResponse());
      await waitForPromises();

      expect(userCalloutDismissSpy).toHaveBeenCalledTimes(2);
    });

    it('deletes the callout even if the dismissal request rejects', async () => {
      const error = new Error('Dismissal failed');
      userCalloutDismissSpy.mockRejectedValue(error);

      await clickUndo();

      expect(Sentry.captureException).toHaveBeenCalledWith(error);
      expect(deleteUserCalloutHandler).toHaveBeenCalledTimes(1);
    });

    it('reports errors returned by the mutation', async () => {
      deleteUserCalloutHandler.mockResolvedValue(deleteUserCalloutResponse(['Some error']));

      await clickUndo();

      expect(Sentry.captureException).toHaveBeenCalledWith(
        new Error('User callout delete failed: Some error'),
      );
    });

    it('reports a failed request', async () => {
      const error = new Error('Network error');
      deleteUserCalloutHandler.mockRejectedValue(error);

      await clickUndo();

      expect(logError).toHaveBeenCalledWith(error);
      expect(Sentry.captureException).toHaveBeenCalledWith(error);
    });
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('tracks the widget view on mount', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      createComponent();

      expect(trackEventSpy).toHaveBeenCalledWith(
        'view_use_gitlab_locally_widget_on_homepage',
        {},
        undefined,
      );
    });

    it.each`
      index | label
      ${0}  | ${'ide_extension'}
      ${1}  | ${'cli'}
    `('tracks expanding the $label item', ({ index, label }) => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findAccordionItems().at(index).vm.$emit('input', true);

      expect(trackEventSpy).toHaveBeenCalledWith(
        'expand_use_gitlab_locally_widget_item',
        { label },
        undefined,
      );
    });

    it('does not track collapsing an item', () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findAccordionItems().at(0).vm.$emit('input', false);

      expect(trackEventSpy).not.toHaveBeenCalledWith(
        'expand_use_gitlab_locally_widget_item',
        expect.anything(),
        undefined,
      );
    });

    it.each`
      id              | label
      ${'vs_code'}    | ${'ide_extension'}
      ${'jetbrains'}  | ${'ide_extension'}
      ${'gitlab_cli'} | ${'cli'}
    `('tracks clicking the $id link', ({ id, label }) => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findLink(id).vm.$emit('click');

      expect(trackEventSpy).toHaveBeenCalledWith(
        'click_use_gitlab_locally_widget_link',
        { label, property: id },
        undefined,
      );
    });

    it('tracks removing the widget', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      await clickRemove();

      expect(trackEventSpy).toHaveBeenCalledWith(
        'dismiss_use_gitlab_locally_widget',
        {},
        undefined,
      );
    });

    it('tracks Undo', async () => {
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      await clickRemove();
      lastToastOptions().action.onClick(null, { hide: mockToastHide });

      expect(trackEventSpy).toHaveBeenCalledWith(
        'undo_dismiss_use_gitlab_locally_widget',
        {},
        undefined,
      );
    });
  });
});
