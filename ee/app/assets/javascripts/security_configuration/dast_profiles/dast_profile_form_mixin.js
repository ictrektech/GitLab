import { isEqual } from 'lodash-es';
import { serializeFormObject } from '~/lib/utils/forms';

export default () => ({
  props: {
    profile: {
      type: Object,
      required: false,
      default: () => ({}),
    },
    projectFullPath: {
      type: String,
      required: true,
    },
    stacked: {
      type: Boolean,
      required: false,
      default: false,
    },
    isProfileInUse: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  computed: {
    isEdit() {
      return Boolean(this.profile.id);
    },
    formTouched() {
      return !isEqual(serializeFormObject(this.form.fields), this.initialFormValues);
    },
    isPolicyProfile() {
      return Boolean(this.profile.referencedInSecurityPolicies?.length);
    },
  },
});
