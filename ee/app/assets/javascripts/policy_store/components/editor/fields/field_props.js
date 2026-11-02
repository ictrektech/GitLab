/**
 * The props every field control receives from ConfigWrapper. `value` stays with each
 * component because its type differs per field type.
 *
 * `config` is the whole entry config, not just this field's slice, so a control can read
 * a sibling's value — needed where one field's shape depends on another's answer. Every
 * control declares it even when it ignores it: an undeclared prop would otherwise fall
 * through and render `config="[object Object]"` on the root element.
 */
export const fieldProps = {
  field: {
    type: Object,
    required: true,
  },
  config: {
    type: Object,
    required: false,
    default: () => ({}),
  },
  // What is wrong with this field's value, or empty when nothing is. Every control
  // declares it for the same reason it declares `config`, and passes it to FieldWrapper.
  error: {
    type: String,
    required: false,
    default: '',
  },
};
