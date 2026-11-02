import { GlCard } from '@gitlab/ui';
import { colorFromDefaultPalette } from '@gitlab/ui/src/utils/charts/theme';
import DonutChart from './donut_chart.vue';
import { LEGEND_POSITION_BOTTOM } from './constants';

// Mock data only. No aggregate exists for either distribution yet.
const agentSlices = [
  { name: 'claude-code', label: 'Claude Code', value: 58 },
  { name: 'cursor', label: 'Cursor', value: 34 },
  { name: 'opencode', label: 'OpenCode', value: 22 },
  { name: 'gemini-cli', label: 'Gemini CLI', value: 18 },
  { name: 'windsurf', label: 'Windsurf', value: 14 },
  { name: 'aider', label: 'Aider', value: 9 },
  { name: 'continue-dev', label: 'Continue.dev', value: 6 },
  { name: 'cline', label: 'Cline', value: 3 },
  { name: 'zed-ai', label: 'Zed AI', value: 2 },
];

const riskSlices = [
  { name: 'read', label: 'Read', value: 146377 },
  { name: 'write', label: 'Write', value: 38020 },
  { name: 'destructive', label: 'Destructive', value: 5703 },
];

// Risk levels are an enumerable set, so their colours are pinned by identity.
const riskColors = {
  read: colorFromDefaultPalette(0),
  write: colorFromDefaultPalette(1),
  destructive: colorFromDefaultPalette(3),
};

const longLabelSlices = [
  { name: 'a', label: 'business_context_security_guidelines', value: 40 },
  { name: 'b', label: 'software_development_with_a_very_long_definition_name', value: 30 },
  { name: 'c', label: 'code_review/v1', value: 20 },
];

export default {
  component: DonutChart,
  title: 'ee/ai/governance/components/dashboard/charts/donut_chart',
};

const template = (args, { argTypes }) => ({
  components: { DonutChart, GlCard },
  props: Object.keys(argTypes),
  template: `
    <gl-card class="gl-max-w-62">
      <template #header>
        <h2 class="gl-m-0 gl-text-base gl-font-bold">{{ cardTitle }}</h2>
      </template>
      <donut-chart v-bind="$props" />
    </gl-card>
  `,
});

export const ManySlicesLegendRight = {
  render: template,
  args: {
    cardTitle: 'Which AI agents developers are using',
    slices: agentSlices,
    centerValue: '166',
    centerCaption: 'developers',
    description: 'Developers by AI agent',
  },
};

export const NineSlicesUnfolded = {
  render: template,
  args: {
    ...ManySlicesLegendRight.args,
    cardTitle: 'Which AI agents developers are using (all nine)',
    maxSlices: agentSlices.length,
  },
};

export const FewSlicesLegendBottom = {
  render: template,
  args: {
    cardTitle: 'Tool calls by action',
    slices: riskSlices,
    sliceColors: riskColors,
    centerValue: '190.1K',
    centerCaption: 'tool calls',
    description: 'Tool calls by action',
    legendPosition: LEGEND_POSITION_BOTTOM,
    showLegendPercentages: true,
  },
};

export const LongLabels = {
  render: template,
  args: {
    cardTitle: 'Agent sessions by type',
    slices: longLabelSlices,
    centerValue: '90',
    centerCaption: 'sessions',
    description: 'Agent sessions by type',
    showLegendPercentages: true,
  },
};

export const Empty = {
  render: template,
  args: {
    cardTitle: 'Tool calls by action',
    slices: [],
    centerValue: '0',
    centerCaption: 'tool calls',
    description: 'Tool calls by action',
  },
};

export const Loading = {
  render: template,
  args: {
    ...ManySlicesLegendRight.args,
    loading: true,
  },
};
