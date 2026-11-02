<script>
import { GlCard, GlTable, GlBadge, GlLink, GlSkeletonLoader, GlSprintf } from '@gitlab/ui';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { s__ } from '~/locale';
import { getSecurityPolicyListUrl } from '~/editor/extensions/source_editor_security_policy_schema_ext';
// TODO: this import chain pulls in Monaco: https://gitlab.com/gitlab-org/gitlab/-/work_items/631828
import ListComponentScope from 'ee/security_orchestration/components/policies/list_component_scope.vue';
import {
  isGroup,
  isPolicyInherited,
  policyHasNamespace,
} from 'ee/security_orchestration/components/utils';
import {
  MODE_ENFORCE,
  MODE_WARN,
  NAMESPACE_GROUP,
  NAMESPACE_PROJECT,
  SOURCE_RELATIONSHIP_DESCENDANT,
} from '../constants';

export default {
  name: 'DependencyFirewallActivePoliciesTable',
  components: {
    GlCard,
    GlTable,
    GlBadge,
    GlLink,
    GlSkeletonLoader,
    GlSprintf,
    ListComponentScope,
    TimeAgoTooltip,
  },
  inject: ['namespaceType'],
  props: {
    items: {
      type: Array,
      required: true,
    },
    loading: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  fields: [
    { key: 'name', label: s__('DependencyFirewall|Policy Name') },
    { key: 'source', label: s__('DependencyFirewall|Source') },
    { key: 'scope', label: s__('DependencyFirewall|Scope') },
    { key: 'mode', label: s__('DependencyFirewall|Mode') },
    { key: 'updatedAt', label: s__('DependencyFirewall|Last Updated') },
  ],
  i18n: {
    definedIn: s__('DependencyFirewall|Defined in %{namespace}'),
    // Same wording as the security policies list.
    inheritedFrom: s__('SecurityOrchestration|Inherited from %{namespace}'),
    inherited: s__('SecurityOrchestration|Inherited'),
    thisGroup: s__('SecurityOrchestration|This group'),
    thisProject: s__('SecurityOrchestration|This project'),
  },
  computed: {
    definedHereLabel() {
      return isGroup(this.namespaceType)
        ? this.$options.i18n.thisGroup
        : this.$options.i18n.thisProject;
    },
  },
  methods: {
    isBlocking(item) {
      return item.mode === MODE_ENFORCE;
    },
    isWarning(item) {
      return item.mode === MODE_WARN;
    },
    modeVariant(item) {
      if (this.isBlocking(item)) return 'danger';
      if (this.isWarning(item)) return 'warning';
      return 'neutral';
    },
    modeLabel(item) {
      if (this.isBlocking(item)) return s__('DependencyFirewall|Blocking');
      if (this.isWarning(item)) return s__('DependencyFirewall|Warning');
      return s__('DependencyFirewall|Unknown mode');
    },
    isDescendant(item) {
      return item.sourceRelationship === SOURCE_RELATIONSHIP_DESCENDANT;
    },
    sourcePath(source) {
      return source.project?.fullPath ?? source.namespace?.fullPath;
    },
    policyListUrl(source) {
      return getSecurityPolicyListUrl({
        namespacePath: this.sourcePath(source),
        namespaceType: source.project ? NAMESPACE_PROJECT : NAMESPACE_GROUP,
      });
    },
    isPolicyInherited,
    policyHasNamespace,
  },
};
</script>

<template>
  <gl-card body-class="gl-px-5 gl-pt-5 gl-pb-2">
    <template #header>
      <div class="gl-flex gl-items-center gl-gap-3">
        <gl-badge variant="neutral" pill data-testid="active-policies-count">
          {{ items.length }}
        </gl-badge>
        <h2 class="gl-m-0 gl-text-base gl-font-bold">
          {{ s__('DependencyFirewall|Active Policies') }}
        </h2>
      </div>
    </template>

    <gl-table
      :items="items"
      :fields="$options.fields"
      :empty-text="s__('DependencyFirewall|No active dependency firewall policies.')"
      :busy="loading"
      show-empty
      stacked="md"
      borderless
      class="gl-border-t-1 gl-border-default gl-border-t-solid"
      data-testid="dependency-firewall-policies-table"
    >
      <template #table-busy>
        <gl-skeleton-loader />
      </template>

      <template #cell(name)="{ item }">
        {{ item.name }}
      </template>

      <template #cell(source)="{ item }">
        <gl-sprintf
          v-if="isDescendant(item) && sourcePath(item.source)"
          :message="$options.i18n.definedIn"
        >
          <template #namespace>
            <gl-link :href="policyListUrl(item.source)">{{ sourcePath(item.source) }}</gl-link>
          </template>
        </gl-sprintf>
        <template v-else-if="isDescendant(item)">
          {{ s__('DependencyFirewall|Defined in a subgroup or project') }}
        </template>
        <gl-sprintf
          v-else-if="isPolicyInherited(item.source) && policyHasNamespace(item.source)"
          :message="$options.i18n.inheritedFrom"
        >
          <template #namespace>
            <gl-link :href="policyListUrl(item.source)">{{ item.source.namespace.name }}</gl-link>
          </template>
        </gl-sprintf>
        <template v-else-if="isPolicyInherited(item.source)">
          {{ $options.i18n.inherited }}
        </template>
        <template v-else>{{ definedHereLabel }}</template>
      </template>

      <template #cell(scope)="{ item }">
        <list-component-scope :policy-scope="item.scope" />
      </template>

      <template #cell(mode)="{ item }">
        <gl-badge :variant="modeVariant(item)">
          {{ modeLabel(item) }}
        </gl-badge>
      </template>

      <template #cell(updatedAt)="{ item }">
        <time-ago-tooltip v-if="item.updatedAt" :time="item.updatedAt" />
      </template>
    </gl-table>
  </gl-card>
</template>
