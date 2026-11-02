<script>
import { computed } from 'vue';
import { getSlotFunction, normalizeRender } from '~/lib/utils/vue3compat/normalize_render';
import statusChecksData, { retryFetch } from './status_checks_data';

export default normalizeRender({
  name: 'StatusChecksProvider',
  mixins: [statusChecksData],
  provide() {
    return {
      isStatusChecksLoading: computed(() => this.isStatusChecksLoading),
      errorMessage: computed(() => this.statusChecksError),
      checks: computed(() => this.statusChecks),
      statusIconName: computed(() => this.statusChecksIcon),
      sections: computed(() => this.statusChecksSections),
      retryFetch,
    };
  },
  props: {
    mr: {
      type: Object,
      required: true,
    },
  },
  render() {
    return getSlotFunction(this)?.();
  },
});
</script>
