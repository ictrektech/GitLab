<script>
import EMPTY_STATE_SVG_URL from '@gitlab/svgs/dist/illustrations/empty-state/empty-pipeline-md.svg?url';

import { GlEmptyState, GlLink, GlSprintf } from '@gitlab/ui';
import EmptyResult from '~/vue_shared/components/empty_result.vue';
import {
  I18N_GET_STARTED,
  I18N_RUNNERS_ARE_AGENTS,
  I18N_CREATE_RUNNER_LINK,
  I18N_CONTACT_ADMIN_TO_REGISTER,
} from '~/ci/runner/constants';

export default {
  name: 'RunnerListEmptyState',
  components: {
    GlEmptyState,
    GlLink,
    GlSprintf,
    EmptyResult,
  },
  props: {
    isSearchFiltered: {
      type: Boolean,
      required: false,
      default: false,
    },
    newRunnerPath: {
      type: String,
      required: false,
      default: null,
    },
  },
  EMPTY_STATE_SVG_URL,

  I18N_GET_STARTED,
  I18N_RUNNERS_ARE_AGENTS,
  I18N_CREATE_RUNNER_LINK,
  I18N_CONTACT_ADMIN_TO_REGISTER,
};
</script>

<template>
  <empty-result v-if="isSearchFiltered" />
  <gl-empty-state
    v-else
    :title="$options.I18N_GET_STARTED"
    :svg-path="$options.EMPTY_STATE_SVG_URL"
    :svg-height="$options.svgHeight"
  >
    <template #description>
      {{ $options.I18N_RUNNERS_ARE_AGENTS }}
      <gl-sprintf v-if="newRunnerPath" :message="$options.I18N_CREATE_RUNNER_LINK">
        <template #link="{ content }">
          <gl-link :href="newRunnerPath">{{ content }}</gl-link>
        </template>
      </gl-sprintf>
      <template v-else>
        {{ $options.I18N_CONTACT_ADMIN_TO_REGISTER }}
      </template>
    </template>
  </gl-empty-state>
</template>
