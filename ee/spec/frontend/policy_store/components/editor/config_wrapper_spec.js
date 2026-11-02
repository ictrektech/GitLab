import { shallowMount } from '@vue/test-utils';
import ConfigWrapper from 'ee/policy_store/components/editor/config_wrapper.vue';
import { FIELD_TYPES } from 'ee/policy_store/components/editor/constants';
import FreezeWindowsConfig from 'ee/policy_store/components/editor/freeze_windows_config.vue';
import MultiBadgeSelector from 'ee/policy_store/components/editor/fields/multi_badge_selector.vue';
import CheckboxField from 'ee/policy_store/components/editor/fields/checkbox_field.vue';
import CodeField from 'ee/policy_store/components/editor/fields/code_field.vue';
import NumberField from 'ee/policy_store/components/editor/fields/number_field.vue';
import SearchableSelectField from 'ee/policy_store/components/editor/fields/searchable_select_field.vue';
import SelectField from 'ee/policy_store/components/editor/fields/select_field.vue';
import SettingExpectationsField from 'ee/policy_store/components/editor/fields/setting_expectations_field.vue';
import TextField from 'ee/policy_store/components/editor/fields/text_field.vue';
import TextListField from 'ee/policy_store/components/editor/fields/text_list_field.vue';
import TextareaField from 'ee/policy_store/components/editor/fields/textarea_field.vue';

describe('ConfigWrapper', () => {
  let wrapper;

  const createComponent = ({ fields = [], value = {}, fieldErrors, showFieldErrors } = {}) => {
    wrapper = shallowMount(ConfigWrapper, {
      propsData: { fields, value, fieldErrors, showFieldErrors },
    });
  };

  describe('dispatch', () => {
    it.each`
      type                      | component
      ${'text'}                 | ${TextField}
      ${'text_list'}            | ${TextListField}
      ${'textarea'}             | ${TextareaField}
      ${'select'}               | ${SelectField}
      ${'searchable_select'}    | ${SearchableSelectField}
      ${'checkbox'}             | ${CheckboxField}
      ${'multi_badge'}          | ${MultiBadgeSelector}
      ${'code'}                 | ${CodeField}
      ${'number'}               | ${NumberField}
      ${'setting_expectations'} | ${SettingExpectationsField}
      ${'freeze_windows'}       | ${FreezeWindowsConfig}
    `('renders the control registered for type $type', ({ type, component }) => {
      createComponent({ fields: [{ key: 'f', type, label: 'F', options: [] }] });

      expect(wrapper.findComponent(component).exists()).toBe(true);
    });

    // catalog_spec only checks catalog types against FIELD_TYPES; rendering is decided by
    // the component map, so a type present in one but not the other must fail here.
    it.each(FIELD_TYPES)('registers a control for the declared type %s', (type) => {
      createComponent({ fields: [{ key: 'f', type, label: 'F', options: [] }] });

      expect(wrapper.find('*').element.children).toHaveLength(1);
    });

    it('renders nothing for a type it has no control for, rather than guessing', () => {
      createComponent({ fields: [{ key: 'f', type: 'named_checkbox_grid', label: 'F' }] });

      expect(wrapper.findComponent(TextField).exists()).toBe(false);
      expect(wrapper.find('*').element.children).toHaveLength(0);
    });

    it('gives each control only its own slice of the value', () => {
      createComponent({
        fields: [
          { key: 'a', type: 'text', label: 'A' },
          { key: 'b', type: 'textarea', label: 'B' },
        ],
        value: { a: 'first', b: 'second' },
      });

      expect(wrapper.findComponent(TextField).props('value')).toBe('first');
      expect(wrapper.findComponent(TextareaField).props('value')).toBe('second');
    });

    it('renders nothing when there are no fields', () => {
      createComponent({ fields: [] });

      expect(wrapper.find('*').element.children).toHaveLength(0);
    });
  });

  describe('field errors', () => {
    const fields = [
      { key: 'branch', type: 'text', label: 'Branch' },
      { key: 'note', type: 'textarea', label: 'Note' },
    ];
    const fieldErrors = { branch: 'Rule is missing Branch.' };

    const edit = (component, value) => wrapper.findComponent(component).vm.$emit('input', value);

    it('says nothing about a field the author has not edited yet', () => {
      createComponent({ fields, fieldErrors });

      expect(wrapper.findComponent(TextField).props('error')).toBe('');
    });

    it('shows the message once the author has edited the field', async () => {
      createComponent({ fields, fieldErrors });

      edit(TextField, 'main');
      await wrapper.setProps({ value: { branch: 'main' } });

      expect(wrapper.findComponent(TextField).props('error')).toBe('Rule is missing Branch.');
    });

    it('keeps the message after the author clears the field again', async () => {
      createComponent({ fields, value: { branch: 'main' }, fieldErrors: {} });

      edit(TextField, '');
      await wrapper.setProps({ value: { branch: '' }, fieldErrors });

      expect(wrapper.findComponent(TextField).props('error')).toBe('Rule is missing Branch.');
    });

    // Opening a row is the author reaching for the control, not answering it, so the
    // control must not go red under the cursor before they have typed anything.
    it('stays quiet while the author only opens an empty expectations row', async () => {
      const expectationFields = [
        { key: 'expectations', type: 'setting_expectations', label: 'Expectations' },
      ];
      const expectationErrors = { expectations: 'Rule is missing Expectations.' };

      createComponent({ fields: expectationFields, fieldErrors: expectationErrors });

      edit(SettingExpectationsField, [{ setting: '', expected: '' }]);
      await wrapper.setProps({ value: { expectations: [{ setting: '', expected: '' }] } });

      expect(wrapper.findComponent(SettingExpectationsField).props('error')).toBe('');

      const started = [{ setting: 'minimum_approvals', expected: '' }];
      edit(SettingExpectationsField, started);
      await wrapper.setProps({ value: { expectations: started } });

      expect(wrapper.findComponent(SettingExpectationsField).props('error')).toBe(
        'Rule is missing Expectations.',
      );
    });

    it('leaves a sibling the author has not touched neutral', async () => {
      createComponent({ fields, fieldErrors: { ...fieldErrors, note: 'Rule is missing Note.' } });

      edit(TextField, 'main');
      await wrapper.setProps({ value: { branch: 'main' } });

      expect(wrapper.findComponent(TextareaField).props('error')).toBe('');
    });

    it('passes nothing on when the entry has no errors', async () => {
      createComponent({ fields });

      edit(TextField, 'main');
      await wrapper.setProps({ value: { branch: 'main' } });

      expect(wrapper.findComponent(TextField).props('error')).toBe('');
    });

    it('reveals every message once the wizard says the author has moved on', () => {
      createComponent({
        fields,
        fieldErrors: { ...fieldErrors, note: 'Rule is missing Note.' },
        showFieldErrors: true,
      });

      expect(wrapper.findComponent(TextField).props('error')).toBe('Rule is missing Branch.');
      expect(wrapper.findComponent(TextareaField).props('error')).toBe('Rule is missing Note.');
    });

    it('still says nothing about a field with no message when revealing', () => {
      createComponent({ fields, fieldErrors, showFieldErrors: true });

      expect(wrapper.findComponent(TextareaField).props('error')).toBe('');
    });

    // The value of a hidden field is discarded, so it comes back blank; an author who
    // never answered it this time round must not find it already red.
    it('forgets a field was touched once an answer hides it', async () => {
      const gated = [
        { key: 'branch', type: 'text', label: 'Branch' },
        {
          key: 'note',
          type: 'textarea',
          label: 'Note',
          showIf: { key: 'branch', in: ['main'] },
        },
      ];

      createComponent({ fields: gated, value: { branch: 'main' }, fieldErrors: {} });

      edit(TextareaField, 'typed');
      await wrapper.setProps({ value: { branch: 'main', note: 'typed' } });
      edit(TextField, 'other');
      await wrapper.setProps({ value: { branch: 'other' } });
      edit(TextField, 'main');
      await wrapper.setProps({
        value: { branch: 'main' },
        fieldErrors: { note: 'Rule is missing Note.' },
      });

      expect(wrapper.findComponent(TextareaField).props('error')).toBe('');
    });

    // `created` seeds declared defaults by emitting directly rather than through `update`,
    // so a seeded-but-blank required field must not open already drawn in red.
    it('does not treat a seeded default as an edit', () => {
      createComponent({
        fields: [{ key: 'branch', type: 'text', label: 'Branch', default: '' }],
        fieldErrors,
      });

      expect(wrapper.findComponent(TextField).props('error')).toBe('');
    });
  });

  describe('sibling config', () => {
    it('gives each control the whole config, not just its own value', () => {
      createComponent({
        fields: [
          { key: 'setting', type: 'text', label: 'Setting' },
          { key: 'expected', type: 'textarea', label: 'Expected' },
        ],
        value: { setting: 'visibility', expected: 'private' },
      });

      expect(wrapper.findComponent(TextField).props('config')).toEqual({
        setting: 'visibility',
        expected: 'private',
      });
    });
  });

  describe('showIf', () => {
    const fields = [
      { key: 'setting', type: 'text', label: 'Setting' },
      {
        key: 'expected',
        type: 'textarea',
        label: 'Expected',
        showIf: { key: 'setting', in: ['visibility'] },
      },
    ];

    it('hides a field whose showIf does not match the sibling value', () => {
      createComponent({ fields, value: { setting: 'other' } });

      expect(wrapper.findComponent(TextareaField).exists()).toBe(false);
    });

    it('hides a field whose showIf sibling has no value yet', () => {
      createComponent({ fields });

      expect(wrapper.findComponent(TextareaField).exists()).toBe(false);
    });

    it('shows the field once the sibling takes a listed value', async () => {
      createComponent({ fields, value: { setting: 'other' } });

      await wrapper.setProps({ value: { setting: 'visibility' } });

      expect(wrapper.findComponent(TextareaField).exists()).toBe(true);
    });

    it('renders a field with no showIf declaration', () => {
      createComponent({ fields, value: { setting: 'other' } });

      expect(wrapper.findComponent(TextField).exists()).toBe(true);
    });
  });

  describe('discarding a hidden value', () => {
    const fields = [
      { key: 'setting', type: 'text', label: 'Setting' },
      {
        key: 'branches',
        type: 'text',
        label: 'Branches',
        showIf: { key: 'setting', in: ['protected_branch'] },
      },
    ];

    it('drops the value of a field the answer just hid', () => {
      createComponent({ fields, value: { setting: 'protected_branch', branches: 'main' } });

      wrapper.findComponent(TextField).vm.$emit('input', 'visibility');

      expect(wrapper.emitted('input')).toEqual([[{ setting: 'visibility' }]]);
    });

    it('does not bring the value back when the sibling is set again', async () => {
      createComponent({ fields, value: { setting: 'protected_branch', branches: 'main' } });

      wrapper.findComponent(TextField).vm.$emit('input', 'visibility');
      await wrapper.setProps({ value: wrapper.emitted('input').at(-1)[0] });
      wrapper.findComponent(TextField).vm.$emit('input', 'protected_branch');

      expect(wrapper.emitted('input').at(-1)[0]).toEqual({ setting: 'protected_branch' });
    });

    // The destructive path: the author edits something unrelated and a value they were
    // never shown leaves with it. Accepted by design, so it needs a spec that says so.
    it('drops a value that arrived already hidden when an unrelated field changes', () => {
      createComponent({
        fields: [...fields, { key: 'note', type: 'textarea', label: 'Note' }],
        value: { setting: 'visibility', branches: 'legacy', note: '' },
      });

      wrapper.findComponent(TextareaField).vm.$emit('input', 'edited');

      expect(wrapper.emitted('input')).toEqual([[{ setting: 'visibility', note: 'edited' }]]);
    });

    it('leaves a key the catalog does not declare alone', () => {
      createComponent({ fields, value: { setting: 'visibility', retired: 'kept' } });

      wrapper.findComponent(TextField).vm.$emit('input', 'other');

      expect(wrapper.emitted('input')).toEqual([[{ setting: 'other', retired: 'kept' }]]);
    });

    it('keeps the values of fields that stay visible', () => {
      createComponent({
        fields: [...fields, { key: 'note', type: 'text', label: 'Note' }],
        value: { setting: 'protected_branch', branches: 'main', note: 'kept' },
      });

      wrapper.findComponent(TextField).vm.$emit('input', 'visibility');

      expect(wrapper.emitted('input')).toEqual([[{ setting: 'visibility', note: 'kept' }]]);
    });
  });

  describe('merging', () => {
    it('merges a control emission into the full value object', () => {
      createComponent({
        fields: [{ key: 'branch', type: 'text', label: 'Branch' }],
        value: { existing: 'kept' },
      });

      wrapper.findComponent(TextField).vm.$emit('input', 'main');

      expect(wrapper.emitted('input')).toEqual([[{ existing: 'kept', branch: 'main' }]]);
    });
  });

  describe('defaults', () => {
    const conditionalDefault = [
      { key: 'setting', type: 'text', label: 'Setting' },
      {
        key: 'denyUnlisted',
        type: 'checkbox',
        label: 'Deny',
        default: true,
        showIf: { key: 'setting', in: ['visibility'] },
      },
    ];

    it('seeds every field declaring a default in a single update', () => {
      createComponent({
        fields: [
          { key: 'policy', type: 'code', label: 'Rego', default: 'package foo' },
          { key: 'denyUnlisted', type: 'checkbox', label: 'Deny unlisted', default: true },
          { key: 'branch', type: 'text', label: 'Branch' },
        ],
      });

      expect(wrapper.emitted('input')).toEqual([[{ policy: 'package foo', denyUnlisted: true }]]);
    });

    it('keeps values already set rather than overwriting them with the default', () => {
      createComponent({
        fields: [{ key: 'denyUnlisted', type: 'checkbox', label: 'Deny', default: true }],
        value: { denyUnlisted: false },
      });

      expect(wrapper.emitted('input')).toBeUndefined();
    });

    // `update` filters on `key in shown`, not on a nullish check: a control emitting any
    // cleared value has put the key there, so it is not re-seeded. `null` is the case that
    // separates the two — a nullish check would hand `main` straight back.
    it.each([[''], [null]])(
      'does not hand a field cleared to %p its default straight back',
      (cleared) => {
        createComponent({
          fields: [{ key: 'branch', type: 'text', label: 'Branch', default: 'main' }],
          value: { branch: 'feature' },
        });

        wrapper.findComponent(TextField).vm.$emit('input', cleared);

        expect(wrapper.emitted('input')).toEqual([[{ branch: cleared }]]);
      },
    );

    it('seeds a default of false, which is a value rather than an absent one', () => {
      createComponent({
        fields: [{ key: 'denyUnlisted', type: 'checkbox', label: 'Deny', default: false }],
      });

      expect(wrapper.emitted('input')).toEqual([[{ denyUnlisted: false }]]);
    });

    // A hidden field holds no value at all, so its default waits until the sibling's
    // answer reveals the control rather than being seeded behind it.
    it('does not seed the default of a field hidden at mount', () => {
      createComponent({ fields: conditionalDefault });

      expect(wrapper.emitted('input')).toBeUndefined();
    });

    // The mount-time twin of the reveal-on-update case: A's own default is what makes B
    // visible, so seeding has to look again after applying it.
    it('seeds a field revealed by another field default, in the same emit', () => {
      createComponent({
        fields: [
          { key: 'setting', type: 'text', label: 'Setting', default: 'visibility' },
          {
            key: 'denyUnlisted',
            type: 'checkbox',
            label: 'Deny',
            default: true,
            showIf: { key: 'setting', in: ['visibility'] },
          },
        ],
      });

      expect(wrapper.emitted('input')).toEqual([[{ setting: 'visibility', denyUnlisted: true }]]);
    });

    it('seeds the default once the sibling reveals the field', () => {
      createComponent({ fields: conditionalDefault });

      wrapper.findComponent(TextField).vm.$emit('input', 'visibility');

      expect(wrapper.emitted('input')).toEqual([[{ setting: 'visibility', denyUnlisted: true }]]);
    });

    // NumberField clears itself to `undefined` rather than to '' or [], so the key stays
    // declared while holding no answer. Re-seeding it would
    // hand the author back the default they deliberately removed, and ConfigWrapper
    // remounts whenever the wizard leaves and re-enters the build step.
    it('does not re-seed the default of a field the author cleared', () => {
      createComponent({
        fields: [{ key: 'approvals', type: 'number', label: 'Approvals', default: 2 }],
        value: { approvals: undefined },
      });

      expect(wrapper.emitted('input')).toBeUndefined();
    });

    it('still seeds a field whose value was persisted as null', () => {
      createComponent({
        fields: [{ key: 'approvals', type: 'number', label: 'Approvals', default: 2 }],
        value: { approvals: null },
      });

      expect(wrapper.emitted('input')).toEqual([[{ approvals: 2 }]]);
    });

    it('emits nothing when no field declares a default', () => {
      createComponent({ fields: [{ key: 'branch', type: 'text', label: 'Branch' }] });

      expect(wrapper.emitted('input')).toBeUndefined();
    });
  });
});
