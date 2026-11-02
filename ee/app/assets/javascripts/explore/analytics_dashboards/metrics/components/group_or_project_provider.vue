<script>
import { __, sprintf } from '~/locale';
import { getSlotFunction, normalizeRender } from '~/lib/utils/vue3compat/normalize_render';
import GetGroupOrProjectQuery from 'ee_else_ce/explore/analytics_dashboards/metrics/graphql/get_group_or_project.query.graphql';

const NAMESPACE_LOAD_ERROR = __('Failed to fetch Namespace: %{fullPath}');

/**
 * Renderless component that resolves a namespace as a group or project
 * given its path name as a property
 */
export default normalizeRender({
  name: 'GroupOrProjectProvider',
  props: {
    fullPath: {
      type: String,
      required: true,
    },
  },
  emits: ['done', 'error'],
  data() {
    return {
      namespace: {},
    };
  },
  apollo: {
    namespace: {
      query: GetGroupOrProjectQuery,
      variables() {
        return { fullPath: this.fullPath };
      },
      update(response) {
        const { group = null, project = null } = response;
        const abilities = (project ?? group)?.userPermissions ?? null;
        return { group, project, isProject: Boolean(project), abilities };
      },
      error() {
        this.$emit('error', sprintf(NAMESPACE_LOAD_ERROR, { fullPath: this.fullPath }));
      },
    },
  },
  computed: {
    loading() {
      return this.$apollo.queries.namespace.loading;
    },
  },
  render() {
    if (this.loading) {
      return getSlotFunction(this)({ isNamespaceLoading: this.loading });
    }

    const { group, project, isProject, abilities } = this.namespace;
    this.$emit('done', { group, project, isProject });

    return getSlotFunction(this)({
      group,
      project,
      isProject,
      abilities,
      isNamespaceLoading: false,
    });
  },
});
</script>
