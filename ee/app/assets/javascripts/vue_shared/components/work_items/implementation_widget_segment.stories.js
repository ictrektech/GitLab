import ImplementationWidgetSegment from './implementation_widget_segment.vue';

export default {
  component: ImplementationWidgetSegment,
  title: 'ee/vue_shared/components/work_items/implementation_widget_segment',
  argTypes: {
    label: { control: { type: 'text' } },
  },
};

const Template = (args) => ({
  components: { ImplementationWidgetSegment },
  props: Object.keys(args),
  template: `
    <implementation-widget-segment v-bind="$props">
      <span class="gl-text-subtle">No decisions yet</span>
    </implementation-widget-segment>
  `,
});

export const Default = Template.bind({});
Default.args = {
  label: 'Decision log',
};

// The help popover the confidence score puts next to its label.
export const WithLabelAppend = () => ({
  components: { ImplementationWidgetSegment },
  template: `
    <implementation-widget-segment label="Confidence">
      <template #label-append>
        <button type="button" aria-label="What is the confidence score?">?</button>
      </template>
      <span>High</span>
    </implementation-widget-segment>
  `,
});

// How the segments read side by side in the AI planning metadata row.
export const MetadataRow = () => ({
  components: { ImplementationWidgetSegment },
  template: `
    <div class="gl-flex gl-gap-6">
      <implementation-widget-segment label="Workplan"><span>Ready</span></implementation-widget-segment>
      <implementation-widget-segment label="Confidence"><span>High</span></implementation-widget-segment>
      <implementation-widget-segment label="Decision log">
        <span class="gl-text-subtle">No decisions yet</span>
      </implementation-widget-segment>
    </div>
  `,
});
