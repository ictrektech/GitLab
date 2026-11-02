import { nextTick } from 'vue';
import { GlButton } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PackageVersionRuleBuilder from 'ee/security_orchestration/components/policy_editor/dependency_firewall/rule/package_version_rule_builder.vue';

describe('PackageVersionRuleBuilder', () => {
  let wrapper;

  const createWrapper = (
    initRule = { type: 'package_version', denied: [{ name: '', version: '' }] },
    props = {},
  ) => {
    wrapper = shallowMountExtended(PackageVersionRuleBuilder, {
      propsData: { initRule, ...props },
    });
  };

  const findName = (index) => wrapper.findComponentByTestId(`package-version-name-${index}`);
  const findVersion = (index) => wrapper.findComponentByTestId(`package-version-version-${index}`);
  const findRemoveButtons = () => wrapper.findAllComponentsByTestId('remove-package-row');
  const findAddButton = () => wrapper.findComponentByTestId('add-package-row');
  const findIncomplete = () => wrapper.findByTestId('incomplete-package-row');

  it('renders the blurb', () => {
    createWrapper();

    expect(wrapper.findByTestId('package-version-blurb').text()).toBe(
      'Deny specific package versions by exact name and version.',
    );
  });

  it('renders one name and version input per denied entry', () => {
    createWrapper({
      type: 'package_version',
      denied: [
        { name: 'lodash', version: '4.17.20' },
        { name: 'express', version: '4.18.0' },
      ],
    });

    expect(findName(0).props('value')).toBe('lodash');
    expect(findVersion(0).props('value')).toBe('4.17.20');
    expect(findName(1).props('value')).toBe('express');
    expect(findVersion(1).props('value')).toBe('4.18.0');
  });

  it('has no allow/deny toggle or exceptions control, only remove and add buttons', () => {
    createWrapper();

    expect(wrapper.findAllComponents(GlButton)).toHaveLength(2);
  });

  describe('when editing', () => {
    beforeEach(() => {
      createWrapper({
        type: 'package_version',
        denied: [
          { name: 'lodash', version: '4.17.20' },
          { name: 'express', version: '4.18.0' },
        ],
      });
    });

    it('updates a name', () => {
      findName(1).vm.$emit('input', 'koa');

      expect(wrapper.emitted('changed')[0][0].denied).toEqual([
        { name: 'lodash', version: '4.17.20' },
        { name: 'koa', version: '4.18.0' },
      ]);
    });

    it('updates a version', () => {
      findVersion(0).vm.$emit('input', '4.17.21');

      expect(wrapper.emitted('changed')[0][0].denied).toEqual([
        { name: 'lodash', version: '4.17.21' },
        { name: 'express', version: '4.18.0' },
      ]);
    });

    it('appends an empty row', () => {
      findAddButton().vm.$emit('click');

      expect(wrapper.emitted('changed')[0][0].denied).toEqual([
        { name: 'lodash', version: '4.17.20' },
        { name: 'express', version: '4.18.0' },
        { name: '', version: '' },
      ]);
    });

    it('removes a row', () => {
      findRemoveButtons().at(0).vm.$emit('click');

      expect(wrapper.emitted('changed')[0][0].denied).toEqual([
        { name: 'express', version: '4.18.0' },
      ]);
    });
  });

  describe.each`
    field        | value
    ${'name'}    | ${'express'}
    ${'version'} | ${'4.18.0'}
  `('when editing the $field with surrounding whitespace', ({ field, value }) => {
    const entry = { name: 'lodash', version: '4.17.20' };
    const findInput = () => wrapper.findByTestId(`package-version-${field}-0`);

    beforeEach(() => {
      wrapper = mountExtended(PackageVersionRuleBuilder, {
        propsData: {
          initRule: { type: 'package_version', denied: [{ ...entry }] },
          isActive: true,
        },
      });
    });

    it('emits the trimmed value and displays it on blur', async () => {
      await findInput().setValue(`  ${value}  `);

      expect(wrapper.emitted('changed')[0][0]).toEqual({
        type: 'package_version',
        denied: [{ ...entry, [field]: value }],
      });

      await findInput().trigger('blur');

      expect(findInput().element.value).toBe(value);
    });

    it('emits an empty value for whitespace-only input and marks the updated rule incomplete', async () => {
      await findInput().setValue('   ');

      const updatedRule = wrapper.emitted('changed')[0][0];
      expect(updatedRule).toEqual({
        type: 'package_version',
        denied: [{ ...entry, [field]: '' }],
      });

      await wrapper.setProps({ initRule: updatedRule });

      expect(findIncomplete().text()).toBe('Enter a name and version for every package.');
      expect(findInput().attributes('aria-invalid')).toBe('true');
    });
  });

  describe('reason and reference link', () => {
    const entries = [
      {
        name: 'lodash',
        version: '4.17.20',
        reason: 'CVE-123',
        reference_link: 'https://example.com/CVE-123',
      },
      { name: 'redis', version: '4.35.09', reason: 'CVE-321' },
    ];
    const findReason = (index) => wrapper.findComponentByTestId(`package-version-reason-${index}`);
    const findLink = (index) => wrapper.findComponentByTestId(`package-version-link-${index}`);
    const findInvalidLink = () => wrapper.findByTestId('invalid-package-link');

    beforeEach(() => {
      createWrapper({ type: 'package_version', denied: entries });
    });

    it('renders the reason and link of each entry', () => {
      expect(findReason(0).props('value')).toBe('CVE-123');
      expect(findLink(0).props('value')).toBe('https://example.com/CVE-123');
      expect(findReason(1).props('value')).toBe('CVE-321');
      expect(findLink(1).props('value')).toBe('');
    });

    it('updates the reason of one entry only', () => {
      findReason(1).vm.$emit('input', 'CVE-999');

      expect(wrapper.emitted('changed')[0][0].denied).toStrictEqual([
        entries[0],
        { ...entries[1], reason: 'CVE-999' },
      ]);
    });

    it('updates the link of one entry only', () => {
      findLink(1).vm.$emit('input', 'https://example.com/CVE-321');

      expect(wrapper.emitted('changed')[0][0].denied).toStrictEqual([
        entries[0],
        { ...entries[1], reference_link: 'https://example.com/CVE-321' },
      ]);
    });

    it.each(['reason', 'reference_link'])('drops the %s key when it is cleared', (key) => {
      const find = key === 'reason' ? findReason : findLink;

      find(0).vm.$emit('input', '');

      const [first] = wrapper.emitted('changed')[0][0].denied;
      expect(first).not.toHaveProperty(key);
      expect(first).toHaveProperty('name', 'lodash');
    });

    it('keeps a reason longer than the limit when the name changes', () => {
      const longReason = 'a'.repeat(30);
      createWrapper({
        type: 'package_version',
        denied: [{ name: 'lodash', version: '4.17.20', reason: longReason }],
      });

      findName(0).vm.$emit('input', 'koa');

      expect(wrapper.emitted('changed')[0][0].denied[0]).toStrictEqual({
        name: 'koa',
        version: '4.17.20',
        reason: longReason,
      });
    });

    it('keeps the reason and link when the name changes', () => {
      findName(0).vm.$emit('input', 'koa');

      expect(wrapper.emitted('changed')[0][0].denied[0]).toStrictEqual({
        ...entries[0],
        name: 'koa',
      });
    });

    describe('when mounted fully', () => {
      beforeEach(() => {
        wrapper = mountExtended(PackageVersionRuleBuilder, {
          propsData: { initRule: { type: 'package_version', denied: entries } },
        });
      });

      it('limits the reason to 20 characters', () => {
        expect(wrapper.findByTestId('package-version-reason-0').attributes('maxlength')).toBe('20');
      });

      it('limits the link to 2048 characters', () => {
        expect(wrapper.findByTestId('package-version-link-0').attributes('maxlength')).toBe('2048');
      });
    });

    describe('with a link that does not start with http or https', () => {
      it.each(['ftp://example.com', 'example.com', 'data:text/plain,x'])(
        'flags %s once the card is checked',
        (link) => {
          wrapper = mountExtended(PackageVersionRuleBuilder, {
            propsData: {
              initRule: {
                type: 'package_version',
                denied: [{ name: 'lodash', version: '4.17.20', reference_link: link }],
              },
              isActive: true,
            },
          });
          const input = wrapper.findByTestId('package-version-link-0');

          expect(findInvalidLink().attributes('id')).toBe('package-version-invalid-link');
          expect(input.attributes('aria-invalid')).toBe('true');
          expect(input.attributes('aria-describedby')).toBe('package-version-invalid-link');
        },
      );

      describe('while the card is unchecked', () => {
        beforeEach(() => {
          wrapper = mountExtended(PackageVersionRuleBuilder, {
            propsData: {
              initRule: {
                type: 'package_version',
                denied: [{ name: 'lodash', version: '4.17.20', reference_link: 'example.com' }],
              },
              isActive: false,
            },
          });
        });

        it('shows no error', () => {
          expect(findInvalidLink().exists()).toBe(false);
        });

        it('does not mark the link input invalid', () => {
          const input = wrapper.findByTestId('package-version-link-0');

          expect(input.attributes('aria-invalid')).toBeUndefined();
          expect(input.attributes('aria-describedby')).toBeUndefined();
        });
      });
    });

    describe('with a reason longer than the limit', () => {
      const mountWithLongReason = (isActive) => {
        wrapper = mountExtended(PackageVersionRuleBuilder, {
          propsData: {
            initRule: {
              type: 'package_version',
              denied: [{ name: 'lodash', version: '4.17.20', reason: 'a'.repeat(21) }],
            },
            isActive,
          },
        });
      };

      describe('once the card is checked', () => {
        beforeEach(() => {
          mountWithLongReason(true);
        });

        it('marks the reason input invalid', () => {
          expect(wrapper.findByTestId('package-version-reason-0').attributes('aria-invalid')).toBe(
            'true',
          );
        });
      });

      describe('while the card is unchecked', () => {
        beforeEach(() => {
          mountWithLongReason(false);
        });

        it('does not mark the reason input invalid', () => {
          expect(
            wrapper.findByTestId('package-version-reason-0').attributes('aria-invalid'),
          ).toBeUndefined();
        });
      });
    });

    describe('with a reason exactly at the limit', () => {
      beforeEach(() => {
        wrapper = mountExtended(PackageVersionRuleBuilder, {
          propsData: {
            initRule: {
              type: 'package_version',
              denied: [{ name: 'lodash', version: '4.17.20', reason: 'a'.repeat(20) }],
            },
            isActive: true,
          },
        });
      });

      it('does not mark the reason input invalid', () => {
        expect(
          wrapper.findByTestId('package-version-reason-0').attributes('aria-invalid'),
        ).toBeUndefined();
      });
    });

    describe('with a link longer than the limit', () => {
      beforeEach(() => {
        wrapper = mountExtended(PackageVersionRuleBuilder, {
          propsData: {
            initRule: {
              type: 'package_version',
              denied: [
                {
                  name: 'lodash',
                  version: '4.17.20',
                  reference_link: `https://example.com/${'a'.repeat(2029)}`,
                },
              ],
            },
            isActive: true,
          },
        });
      });

      it('flags the link and names the limit in the message', () => {
        const input = wrapper.findByTestId('package-version-link-0');

        expect(input.attributes('aria-invalid')).toBe('true');
        expect(findInvalidLink().text()).toContain('2048');
      });
    });

    describe('with a link exactly at the limit', () => {
      beforeEach(() => {
        createWrapper(
          {
            type: 'package_version',
            denied: [
              {
                name: 'lodash',
                version: '4.17.20',
                reference_link: `https://example.com/${'a'.repeat(2028)}`,
              },
            ],
          },
          { isActive: true },
        );
      });

      it('shows no error', () => {
        expect(findInvalidLink().exists()).toBe(false);
      });
    });

    it('shows no error for an entry without a link once the card is checked', () => {
      createWrapper(
        { type: 'package_version', denied: [{ name: 'lodash', version: '4.17.20' }] },
        { isActive: true },
      );

      expect(findInvalidLink().exists()).toBe(false);
    });

    it.each(['https://example.com/CVE-123', 'http://example.com'])(
      'shows no error for the valid link %s',
      (link) => {
        createWrapper(
          {
            type: 'package_version',
            denied: [{ name: 'lodash', version: '4.17.20', reference_link: link }],
          },
          { isActive: true },
        );

        expect(findInvalidLink().exists()).toBe(false);
      },
    );
  });

  describe.each`
    field               | testId                        | value
    ${'reason'}         | ${'package-version-reason-0'} | ${'CVE-123'}
    ${'reference_link'} | ${'package-version-link-0'}   | ${'https://example.com/CVE-123'}
  `('when editing the $field with surrounding whitespace', ({ field, testId, value }) => {
    const entry = { name: 'lodash', version: '4.17.20' };
    const findInput = () => wrapper.findByTestId(testId);

    beforeEach(() => {
      wrapper = mountExtended(PackageVersionRuleBuilder, {
        propsData: { initRule: { type: 'package_version', denied: [{ ...entry }] } },
      });
    });

    it('emits the trimmed value and displays it on blur', async () => {
      await findInput().setValue(`  ${value}  `);

      expect(wrapper.emitted('changed')[0][0].denied).toStrictEqual([{ ...entry, [field]: value }]);

      await findInput().trigger('blur');

      expect(findInput().element.value).toBe(value);
    });

    it('drops the key when whitespace replaces an existing value', async () => {
      wrapper = mountExtended(PackageVersionRuleBuilder, {
        propsData: {
          initRule: { type: 'package_version', denied: [{ ...entry, [field]: value }] },
        },
      });

      await findInput().setValue('   ');

      expect(wrapper.emitted('changed')[0][0].denied).toStrictEqual([entry]);
    });
  });

  describe('labels and help text', () => {
    const mountWith = (denied) => {
      wrapper = mountExtended(PackageVersionRuleBuilder, {
        propsData: { initRule: { type: 'package_version', denied } },
      });
    };
    const labelFor = (id) => wrapper.find(`label[for="${id}"]`);

    describe('with one entry that has a reason', () => {
      beforeEach(() => {
        mountWith([{ name: 'lodash', version: '4.17.20', reason: 'CVE-123' }]);
      });

      it.each`
        field        | text
        ${'name'}    | ${'Package name'}
        ${'version'} | ${'Package version'}
        ${'reason'}  | ${'Reason'}
        ${'link'}    | ${'Reference link'}
      `('gives the $field input a visible "$text" label', ({ field, text }) => {
        expect(labelFor(`package-version-${field}-input-0`).text()).toContain(text);
      });

      it.each(['reason', 'link'])('marks the %s input as optional', (field) => {
        expect(labelFor(`package-version-${field}-input-0`).text()).toContain('(optional)');
      });

      it.each(['name', 'version'])('does not mark the %s input as optional', (field) => {
        expect(labelFor(`package-version-${field}-input-0`).text()).not.toContain('(optional)');
      });

      it('explains what the reason and link are for', () => {
        expect(wrapper.text()).toContain('Shown to developers when this package is blocked.');
        expect(wrapper.text()).toContain(
          'Stored with the rule. Must start with http:// or https://.',
        );
      });

      it.each(['name', 'version', 'reason', 'link'])(
        'shows no example placeholder in the %s input',
        (field) => {
          expect(wrapper.findByTestId(`package-version-${field}-0`).attributes('placeholder')).toBe(
            undefined,
          );
        },
      );

      it('counts the characters left for the reason', () => {
        expect(wrapper.text()).toContain('13 characters remaining.');
      });

      it('describes the reason input with the character count', async () => {
        await nextTick();
        const describedBy = wrapper
          .findByTestId('package-version-reason-0')
          .attributes('aria-describedby');
        const ids = describedBy.split(' ');
        const description = ids.map((id) => wrapper.find(`#${id}`).text()).join(' ');

        expect(description).toContain('13 characters remaining.');
        expect(ids).not.toContain('package-version-reason-count-0');
      });
    });

    it('uses the singular when one character is left', () => {
      mountWith([{ name: 'lodash', version: '4.17.20', reason: 'a'.repeat(19) }]);

      expect(wrapper.text()).toContain('1 character remaining.');
    });

    it('reports how far a hand-written reason is over the limit', () => {
      mountWith([{ name: 'lodash', version: '4.17.20', reason: 'a'.repeat(25) }]);

      expect(wrapper.text()).toContain('5 characters over limit.');
    });

    it('labels every entry separately', () => {
      mountWith([
        { name: 'lodash', version: '4.17.20' },
        { name: 'redis', version: '4.35.09' },
      ]);

      expect(labelFor('package-version-reason-input-0').exists()).toBe(true);
      expect(labelFor('package-version-reason-input-1').exists()).toBe(true);
    });
  });

  describe('incomplete rows', () => {
    it('shows no error while the card is unchecked', () => {
      createWrapper(undefined, { isActive: false });

      expect(findIncomplete().exists()).toBe(false);
    });

    it.each`
      reason               | denied
      ${'a blank name'}    | ${[{ name: '', version: '1.0.0' }]}
      ${'a blank version'} | ${[{ name: 'lodash', version: '' }]}
      ${'no rows at all'}  | ${[]}
    `('shows an error once checked with $reason', ({ denied }) => {
      createWrapper({ type: 'package_version', denied }, { isActive: true });

      expect(findIncomplete().exists()).toBe(true);
    });

    it('shows no error once every row is complete', () => {
      createWrapper(
        { type: 'package_version', denied: [{ name: 'lodash', version: '4.17.20' }] },
        { isActive: true },
      );

      expect(findIncomplete().exists()).toBe(false);
    });

    it('flags only the blank field as invalid', () => {
      wrapper = mountExtended(PackageVersionRuleBuilder, {
        propsData: {
          initRule: { type: 'package_version', denied: [{ name: 'lodash', version: '' }] },
          isActive: true,
        },
      });

      expect(wrapper.findByTestId('package-version-name-0').attributes('aria-invalid')).toBe(
        undefined,
      );
      expect(wrapper.findByTestId('package-version-version-0').attributes('aria-invalid')).toBe(
        'true',
      );
    });
  });

  describe('accessibility', () => {
    const mountBuilder = (denied, props = {}) => {
      wrapper = mountExtended(PackageVersionRuleBuilder, {
        propsData: { initRule: { type: 'package_version', denied }, ...props },
      });
    };
    const findInput = (testId) => wrapper.findByTestId(testId);
    const removeLabels = () =>
      wrapper
        .findAllByTestId('remove-package-row')
        .wrappers.map((button) => button.attributes('aria-label'));

    describe('with two rows', () => {
      beforeEach(() => {
        mountBuilder([
          { name: 'lodash', version: '4.17.20' },
          { name: 'express', version: '4.18.0' },
        ]);
      });

      it('groups each entry under its row', () => {
        expect(findInput('package-version-entry-0').attributes('role')).toBe('group');
        expect(findInput('package-version-entry-0').attributes('aria-label')).toBe(
          'Package (row 1)',
        );
        expect(findInput('package-version-entry-1').attributes('aria-label')).toBe(
          'Package (row 2)',
        );
      });

      it.each(['name', 'version', 'reason', 'link'])(
        'names the %s input by its visible label only',
        (field) => {
          expect(findInput(`package-version-${field}-0`).attributes('aria-label')).toBeUndefined();
        },
      );

      it('names the package in each remove button', () => {
        expect(removeLabels()).toEqual(['Remove lodash 4.17.20', 'Remove express 4.18.0']);
      });
    });

    it.each`
      reason                      | entry                               | label
      ${'a blank row'}            | ${{ name: '', version: '' }}        | ${'Remove'}
      ${'a name without version'} | ${{ name: 'lodash', version: '' }}  | ${'Remove lodash'}
      ${'a version without name'} | ${{ name: '', version: '4.17.20' }} | ${'Remove 4.17.20'}
      ${'special characters'}     | ${{ name: 'a&b<c>', version: '1' }} | ${'Remove a&b<c> 1'}
    `('labels the remove button for $reason as "$label"', ({ entry, label }) => {
      mountBuilder([entry]);

      expect(removeLabels()).toEqual([label]);
    });

    describe('when the card is checked', () => {
      it.each`
        blank        | entry                               | blankInput                     | filledInput
        ${'version'} | ${{ name: 'lodash', version: '' }}  | ${'package-version-version-0'} | ${'package-version-name-0'}
        ${'name'}    | ${{ name: '', version: '4.17.20' }} | ${'package-version-name-0'}    | ${'package-version-version-0'}
      `(
        'points only the blank $blank input at the error message',
        ({ entry, blankInput, filledInput }) => {
          mountBuilder([entry], { isActive: true });
          const errorId = findIncomplete().attributes('id');

          expect(errorId).toBe('package-version-incomplete-row');
          expect(findInput(blankInput).attributes('aria-describedby')).toBe(errorId);
          expect(findInput(filledInput).attributes('aria-describedby')).toBeUndefined();
        },
      );
    });

    it('describes no input while the card is unchecked', () => {
      mountBuilder([{ name: '', version: '' }], { isActive: false });

      expect(findInput('package-version-name-0').attributes('aria-describedby')).toBeUndefined();
      expect(findInput('package-version-version-0').attributes('aria-describedby')).toBeUndefined();
    });
  });
});
