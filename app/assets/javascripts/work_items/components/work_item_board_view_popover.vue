<script>
import { GlBadge, GlLink, GlPopover } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';

export default {
  name: 'WorkItemBoardViewPopover',
  helpPath: helpPagePath('user/work_items/saved_views'),
  components: { GlBadge, GlLink, GlPopover },
  props: {
    target: {
      type: Function,
      required: true,
    },
  },
};
</script>

<template>
  <gl-popover
    :target="target"
    placement="bottom"
    boundary="viewport"
    triggers="hover focus"
    data-testid="board-view-popover"
  >
    <template #title>
      <div class="gl-flex gl-items-center gl-gap-3">
        {{ s__('WorkItemPlanningView|Board view') }}
        <gl-badge variant="info" size="small">{{ s__('WorkItemPlanningView|New') }}</gl-badge>
      </div>
    </template>
    <p class="gl-mb-3">
      {{
        s__(
          'WorkItemPlanningView|View your work items as a board, with the same filters and saved views as the list.',
        )
      }}
    </p>
    <gl-link :href="$options.helpPath">{{
      s__('WorkItemPlanningView|Learn more about board view')
    }}</gl-link>
  </gl-popover>
</template>
