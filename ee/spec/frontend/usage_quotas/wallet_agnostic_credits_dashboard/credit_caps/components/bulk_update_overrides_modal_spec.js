import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlFormTextarea, GlModal } from '@gitlab/ui';
import BulkUpdateOverridesModal from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/components/bulk_update_overrides_modal.vue';
import upsertUserOverridesMutation from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/graphql/upsert_user_overrides.mutation.graphql';
import * as utils from 'ee/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/utils';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import createMockApollo from 'helpers/mock_apollo_helper';
import { logError } from '~/lib/logger';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import toast from '~/vue_shared/plugins/global_toast';
import {
  mockUpsertUserOverridesSuccess,
  mockUpsertUserOverridesErrors,
  mockUpsertUserOverridesMultipleErrors,
} from 'ee_jest/usage_quotas/wallet_agnostic_credits_dashboard/credit_caps/mock_data';

jest.mock('~/lib/logger');
jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/vue_shared/plugins/global_toast');

Vue.use(VueApollo);

describe('CreditCapsBulkUpdateOverridesModal', () => {
  /** @type {import('helpers/vue_test_utils_helper').ExtendedWrapper} */
  let wrapper;
  /** @type {jest.Mock} */
  let upsertUserOverridesHandler;

  const createComponent = ({ props = {} } = {}) => {
    const apolloProvider = createMockApollo([
      [upsertUserOverridesMutation, upsertUserOverridesHandler],
    ]);

    wrapper = shallowMountExtended(BulkUpdateOverridesModal, {
      apolloProvider,
      propsData: { visible: true, ...props },
      provide: { namespacePath: 'my-group' },
      stubs: { GlAlert, GlModal, GlFormTextarea },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findTextarea = () => wrapper.findByTestId('bulk-update-overrides-textarea');
  const findErrorsAlert = () => wrapper.findByTestId('bulk-update-overrides-errors-alert');
  const submitForm = () => wrapper.find('form').trigger('submit');

  beforeEach(() => {
    upsertUserOverridesHandler = jest.fn().mockResolvedValue(mockUpsertUserOverridesSuccess);
    createComponent();
  });

  it('renders the modal', () => {
    expect(findModal().exists()).toBe(true);
  });

  it('passes visible prop to modal', () => {
    expect(findModal().props('visible')).toBe(true);
  });

  it('renders the textarea', () => {
    expect(findTextarea().exists()).toBe(true);
  });

  it('starts with an empty textarea', () => {
    expect(findTextarea().element.value).toBe('');
  });

  it('does not show errors initially', () => {
    expect(findErrorsAlert().exists()).toBe(false);
  });

  it('submit button is disabled when textarea is empty', () => {
    expect(findModal().props('actionPrimary').attributes.disabled).toBe(true);
  });

  it('submit button is enabled when textarea has content', async () => {
    await findTextarea().setValue('user1,100,true');

    expect(findModal().props('actionPrimary').attributes.disabled).toBe(false);
  });

  describe('when visible is false', () => {
    beforeEach(() => {
      createComponent({ props: { visible: false } });
    });

    it('passes visible false to modal', () => {
      expect(findModal().props('visible')).toBe(false);
    });
  });

  describe('when modal emits hidden', () => {
    beforeEach(async () => {
      // prettier-ignore
      await findTextarea().setValue([
        'user1,100,true',
      ].join('\n'));
      findModal().vm.$emit('hidden');
      await nextTick();
    });

    it('emits hidden', () => {
      expect(wrapper.emitted('hidden')).toHaveLength(1);
    });

    it('resets the textarea', () => {
      expect(findTextarea().element.value).toBe('');
    });

    it('resets errors', async () => {
      // prettier-ignore
      await findTextarea().setValue([
        'user1,bad,true',
      ].join('\n'));
      await submitForm();
      findModal().vm.$emit('hidden');
      await nextTick();

      expect(findErrorsAlert().exists()).toBe(false);
    });
  });

  describe('when saving is in progress and hidden is emitted', () => {
    beforeEach(async () => {
      upsertUserOverridesHandler = jest.fn().mockReturnValue(new Promise(() => {}));
      createComponent();
      // prettier-ignore
      await findTextarea().setValue([
        'user1,100,true',
      ].join('\n'));
      submitForm();
      await nextTick();
    });

    it('shows a toast and does not reset', async () => {
      findModal().vm.$emit('hidden');
      await nextTick();

      expect(toast).toHaveBeenCalledWith(expect.stringContaining('background'));
      expect(findTextarea().element.value).not.toBe('');
    });
  });

  describe('form submission', () => {
    describe('with valid input', () => {
      beforeEach(async () => {
        // prettier-ignore
        await findTextarea().setValue([
          'user1,100,true',
          'user2,50,false',
        ].join('\n'));
        submitForm();
        await waitForPromises();
      });

      it('calls the mutation with the correct variables', () => {
        expect(upsertUserOverridesHandler).toHaveBeenCalledWith({
          namespacePath: 'my-group',
          overrides: [
            { username: 'user1', cap: 100, enabled: true },
            { username: 'user2', cap: 50, enabled: false },
          ],
        });
      });

      it('shows a success toast', () => {
        expect(toast).toHaveBeenCalledWith(expect.stringContaining('saved'));
      });

      it('emits saved then hidden', () => {
        expect(wrapper.emitted('saved')).toHaveLength(1);
        expect(wrapper.emitted('hidden')).toHaveLength(1);
      });

      it('resets the textarea', () => {
        expect(findTextarea().element.value).toBe('');
      });

      it('does not show errors', () => {
        expect(findErrorsAlert().exists()).toBe(false);
      });
    });

    describe('with empty input', () => {
      beforeEach(async () => {
        await findTextarea().setValue('');
        await submitForm();
      });

      it("doesn't process empty input", () => {
        expect(findErrorsAlert().exists()).toBe(false);
        expect(upsertUserOverridesHandler).not.toHaveBeenCalled();
      });
    });

    describe('when parser returns zero overrides', () => {
      beforeEach(async () => {
        // onSubmit has a shortcircuit for empty inputs
        // Here we mimic a case when input is non-empty,
        // but parser returns an empty result
        jest.spyOn(utils, 'parseOverridesCsv').mockReturnValueOnce({ overrides: [], errors: [] });
        await findTextarea().setValue('username,cap,enabled');
        await submitForm();
      });

      it('shows an error', () => {
        expect(findErrorsAlert().exists()).toBe(true);
        expect(findErrorsAlert().text()).toContain('No overrides to save');
      });
    });

    describe('with invalid CSV input', () => {
      beforeEach(async () => {
        // prettier-ignore
        await findTextarea().setValue([
          'user1,notanumber,true',
        ].join('\n'));
        await submitForm();
      });

      it('does not call the mutation', () => {
        expect(upsertUserOverridesHandler).not.toHaveBeenCalled();
      });

      it('shows errors', () => {
        expect(findErrorsAlert().exists()).toBe(true);
      });

      it('replaces errors on the next invalid submission', async () => {
        // prettier-ignore
        const csv = [
          'user2,bad,true',
          'user3,also_bad,true',
        ].join('\n');

        await findTextarea().setValue(csv);
        await submitForm();

        expect(findErrorsAlert().findAll('li')).toHaveLength(2);
      });
    });

    describe('when over the 200-entry limit', () => {
      beforeEach(async () => {
        const lines = Array.from({ length: 201 }, (_, i) => `user${i},100,true`).join('\n');
        await findTextarea().setValue(lines);
        await submitForm();
      });

      it('does not call the mutation', () => {
        expect(upsertUserOverridesHandler).not.toHaveBeenCalled();
      });

      it('shows an error about the limit', () => {
        expect(findErrorsAlert().exists()).toBe(true);
        expect(findErrorsAlert().text()).toContain('200');
      });
    });

    describe('when the mutation returns errors', () => {
      beforeEach(async () => {
        upsertUserOverridesHandler = jest.fn().mockResolvedValue(mockUpsertUserOverridesErrors);
        createComponent();
        // prettier-ignore
        await findTextarea().setValue([
          'user1,100,true',
        ].join('\n'));
        submitForm();
        await waitForPromises();
      });

      it('does not emit saved', () => {
        expect(wrapper.emitted('saved')).toBeUndefined();
      });

      it('shows the errors alert', () => {
        expect(findErrorsAlert().exists()).toBe(true);
        expect(findErrorsAlert().text()).toContain('Something went wrong');
      });
    });

    describe('when the mutation returns multiple errors', () => {
      beforeEach(async () => {
        upsertUserOverridesHandler = jest
          .fn()
          .mockResolvedValue(mockUpsertUserOverridesMultipleErrors);
        createComponent();
        // prettier-ignore
        await findTextarea().setValue([
          'user1,100,true',
        ].join('\n'));
        submitForm();
        await waitForPromises();
      });

      it('shows all errors', () => {
        expect(findErrorsAlert().findAll('li')).toHaveLength(2);
      });
    });

    describe('when the mutation throws a network error', () => {
      beforeEach(async () => {
        upsertUserOverridesHandler = jest.fn().mockRejectedValue(new Error('Network error'));
        createComponent();
        // prettier-ignore
        await findTextarea().setValue([
          'user1,100,true',
        ].join('\n'));
        submitForm();
        await waitForPromises();
      });

      it('shows the error', () => {
        expect(findErrorsAlert().exists()).toBe(true);
        expect(findErrorsAlert().text()).toContain('Network error');
      });

      it('logs and captures the error', () => {
        expect(logError).toHaveBeenCalled();
        expect(captureException).toHaveBeenCalled();
      });
    });
  });
});
