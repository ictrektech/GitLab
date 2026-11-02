import { GlLoadingIcon } from '@gitlab/ui';
import { GlChart } from '@gitlab/ui/src/charts';
import { GL_COLOR_NEUTRAL_400 } from '@gitlab/ui/src/tokens/build/js/tokens';
import { defaultFontFamily } from '@gitlab/ui/src/utils/charts/theme';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { assertProps } from 'helpers/assert_props';
import DonutChart from 'ee/ai/governance/components/dashboard/charts/donut_chart.vue';
import { DONUT_SLICE_LIMIT } from 'ee/ai/governance/components/dashboard/charts/constants';

describe('DonutChart', () => {
  let wrapper;

  const threeSlices = [
    { name: 'read', label: 'Read', value: 146377 },
    { name: 'write', label: 'Write', value: 38020 },
    { name: 'destructive', label: 'Destructive', value: 5703 },
  ];

  const nineSlices = [
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

  const createComponent = (props = {}) => {
    wrapper = mountExtended(DonutChart, {
      propsData: {
        slices: threeSlices,
        centerValue: '190.1K',
        centerCaption: 'tool calls',
        description: 'Tool calls by risk level',
        ...props,
      },
      stubs: { GlChart: true },
    });
  };

  const findChart = () => wrapper.findComponent(GlChart);
  const findChartWrapper = () => wrapper.findByTestId('donut-chart');
  const findLegend = () => wrapper.findByTestId('donut-legend');
  const findLegendItems = () => wrapper.findAllByTestId('donut-legend-item');
  const findSwatches = () => wrapper.findAllByTestId('donut-legend-swatch');
  const findTable = () => wrapper.findByTestId('donut-table');
  const findEmptyState = () => wrapper.findByTestId('donut-empty-state');
  const chartOptions = () => findChart().props('options');
  const seriesData = () => chartOptions().series[0].data;
  const graphicById = (id) => chartOptions().graphic.find((item) => item.id === id);
  const swatchColors = () =>
    findSwatches().wrappers.map((swatch) => swatch.attributes('style').trim());
  // Let jsdom normalise the colour, so the spec follows the token rather than its hex value.
  const swatchStyleFor = (color) => {
    const element = document.createElement('span');
    element.style.backgroundColor = color;
    return element.getAttribute('style');
  };
  const legendTexts = () =>
    findLegendItems().wrappers.map((item) => item.text().replace(/\s+/g, ' ').trim());

  describe('default rendering', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders one legend entry per slice, using the slice labels', () => {
      expect(legendTexts()).toEqual(['Read', 'Write', 'Destructive']);
    });

    it('plots the slices in value order', () => {
      expect(seriesData().map(({ name, value }) => [name, value])).toEqual([
        ['Read', 146377],
        ['Write', 38020],
        ['Destructive', 5703],
      ]);
    });

    it('renders a 2px-gapped donut ring rather than a filled pie', () => {
      const [series] = chartOptions().series;

      expect(series.type).toBe('pie');
      expect(series.radius).toEqual(['62%', '92%']);
      expect(series.padAngle).toBe(2);
    });

    it('renders the centre value and caption', () => {
      expect(graphicById('donut-center-value').style.text).toBe('190.1K');
      expect(graphicById('donut-center-caption').style.text).toBe('tool calls');
    });

    it('sets the centre text in the chart font', () => {
      expect(graphicById('donut-center-value').style.fontFamily).toBe(defaultFontFamily);
      expect(graphicById('donut-center-caption').style.fontFamily).toBe(defaultFontFamily);
    });

    it('does not show percentages in the legend', () => {
      expect(findLegend().text()).not.toContain('%');
    });

    it('exposes a per-slice tooltip with the value and its share', () => {
      expect(chartOptions().tooltip.trigger).toBe('item');
      expect(chartOptions().tooltip.formatter({ dataIndex: 1 })).toBe('Write: 38,020 (20%)');
    });

    it('confines the tooltip to the viewport', () => {
      expect(chartOptions().tooltip.confine).toBe(true);
    });

    it('escapes slice labels in the tooltip', () => {
      createComponent({ slices: [{ name: 'a', label: '<script>alert(1)</script>', value: 1 }] });

      expect(chartOptions().tooltip.formatter({ dataIndex: 0 })).toBe(
        '&lt;script&gt;alert(1)&lt;/script&gt;: 1 (100%)',
      );
    });
  });

  describe('centre text updates', () => {
    // `setOption` merges, so a graphic without a stable id would leave the old
    // centre text painted underneath the new one.
    it('keeps the graphic ids stable when the centre value changes', async () => {
      createComponent();
      await wrapper.setProps({ centerValue: '2' });

      expect(chartOptions().graphic.map(({ id }) => id)).toEqual([
        'donut-center-value',
        'donut-center-caption',
      ]);
      expect(graphicById('donut-center-value').style.text).toBe('2');
    });
  });

  describe('colour', () => {
    // Colours follow the slice name (destructive, read, write alphabetically),
    // not the slice's size, so Read takes the second palette entry, not the first.
    it('takes the palette colours in fixed order, keyed on the slice name', () => {
      createComponent();

      expect(swatchColors()).toEqual([
        'background-color: rgb(177, 79, 24);',
        'background-color: rgb(0, 144, 177);',
        'background-color: rgb(97, 122, 226);',
      ]);
    });

    it('honours explicit slice colours', () => {
      createComponent({ sliceColors: { read: '#111111', write: '#222222' } });

      expect(swatchColors()).toEqual([
        'background-color: rgb(17, 17, 17);',
        'background-color: rgb(34, 34, 34);',
        'background-color: rgb(97, 122, 226);',
      ]);
    });

    // Index 0 is identical in both palettes, so the assertion has to look at a
    // later slice to prove the dark palette was the one used.
    it('paints from the dark palette in dark mode', () => {
      document.documentElement.classList.add('gl-dark');

      try {
        createComponent();

        expect(swatchColors()).toEqual([
          'background-color: rgb(224, 126, 65);',
          'background-color: rgb(0, 144, 177);',
          'background-color: rgb(97, 122, 226);',
        ]);
      } finally {
        document.documentElement.classList.remove('gl-dark');
      }
    });

    it('does not repaint slices when their ranking changes', () => {
      const colorsByLabel = () =>
        Object.fromEntries(
          findLegendItems().wrappers.map((item) => [
            item.text().trim(),
            item.find('[data-testid="donut-legend-swatch"]').attributes('style').trim(),
          ]),
        );

      createComponent();
      const before = colorsByLabel();

      createComponent({
        slices: [
          { name: 'read', label: 'Read', value: 1 },
          { name: 'write', label: 'Write', value: 900 },
          { name: 'destructive', label: 'Destructive', value: 40 },
        ],
      });

      expect(colorsByLabel()).toEqual(before);
    });
  });

  describe('when there are more slices than maxSlices', () => {
    beforeEach(() => {
      createComponent({ slices: nineSlices, showLegendPercentages: true });
    });

    it('shows maxSlices slices plus a neutral "Other" slice', () => {
      expect(legendTexts()).toEqual([
        'Claude Code 35%',
        'Cursor 21%',
        'OpenCode 13%',
        'Gemini CLI 11%',
        'Windsurf 8%',
        'Other 12%',
      ]);
      expect(swatchColors().at(-1)).toBe(swatchStyleFor(GL_COLOR_NEUTRAL_400));
    });

    it('folds the remainder into the "Other" value', () => {
      expect(seriesData().at(-1)).toMatchObject({ name: 'Other', value: 20 });
    });

    it('shows percentages that total 100', () => {
      const percentages = findLegendItems().wrappers.map((item) =>
        Number(item.text().match(/(\d+)%$/)[1]),
      );

      expect(percentages.reduce((total, value) => total + value, 0)).toBe(100);
    });

    it('accepts a maxSlices above the readability default', () => {
      expect(() =>
        assertProps(DonutChart, {
          slices: nineSlices,
          centerValue: '1',
          centerCaption: 'sessions',
          description: 'Sessions',
          maxSlices: 9,
        }),
      ).not.toThrow();
    });

    it('rejects a maxSlices the palette cannot colour', () => {
      expect(() =>
        assertProps(DonutChart, {
          slices: nineSlices,
          centerValue: '1',
          centerCaption: 'sessions',
          description: 'Sessions',
          maxSlices: DONUT_SLICE_LIMIT + 1,
        }),
      ).toThrow(expect.objectContaining({ message: expect.stringContaining('maxSlices') }));
    });
  });

  describe('when maxSlices is raised above the default', () => {
    beforeEach(() => {
      createComponent({ slices: nineSlices, maxSlices: 9 });
    });

    it('plots every slice with no "Other" fold', () => {
      expect(legendTexts()).toEqual([
        'Claude Code',
        'Cursor',
        'OpenCode',
        'Gemini CLI',
        'Windsurf',
        'Aider',
        'Continue.dev',
        'Cline',
        'Zed AI',
      ]);
    });

    it('gives each of the nine slices its own colour', () => {
      expect(new Set(swatchColors()).size).toBe(9);
    });
  });

  describe('when percentageTotal is set', () => {
    // Three developers, one of whom used two agents, so the slices sum to 4.
    beforeEach(() => {
      createComponent({
        slices: [
          { name: 'gitlab_duo', label: 'GitLab Duo', value: 2 },
          { name: 'claude-code', label: 'Claude Code', value: 1 },
          { name: 'unknown', label: 'Unknown', value: 1 },
        ],
        centerValue: '3',
        centerCaption: 'developers',
        percentageTotal: 3,
        showLegendPercentages: true,
      });
    });

    it('shows each slice as a share of the total in the legend', () => {
      expect(legendTexts()).toEqual(['GitLab Duo 67%', 'Claude Code 33%', 'Unknown 33%']);
    });

    it('uses the same shares in the tooltip and the screen-reader list', () => {
      expect(chartOptions().tooltip.formatter({ dataIndex: 0 })).toBe('GitLab Duo: 2 (67%)');
      expect(
        findTable()
          .findAll('li')
          .wrappers.slice(2)
          .map((row) => row.text()),
      ).toEqual(['GitLab Duo: 2 (67%)', 'Claude Code: 1 (33%)', 'Unknown: 1 (33%)']);
    });

    it('keeps the ring and the centre value unchanged', () => {
      expect(seriesData().map(({ value }) => value)).toEqual([2, 1, 1]);
      expect(graphicById('donut-center-value').style.text).toBe('3');
    });
  });

  describe('with preserveOrder', () => {
    const unorderedSlices = [
      { name: 'destructive', label: 'Destructive', value: 5703 },
      { name: 'none', label: 'None', value: 0 },
      { name: 'read', label: 'Read', value: 146377 },
      { name: 'write', label: 'Write', value: 38020 },
    ];

    it('orders by value when not set', () => {
      createComponent({ slices: unorderedSlices });

      expect(legendTexts()).toEqual(['Read', 'Write', 'Destructive']);
    });

    it('keeps the input order in the legend and the ring, dropping empty slices', () => {
      createComponent({ slices: unorderedSlices, preserveOrder: true });

      expect(legendTexts()).toEqual(['Destructive', 'Read', 'Write']);
      expect(seriesData().map(({ name, value }) => [name, value])).toEqual([
        ['Destructive', 5703],
        ['Read', 146377],
        ['Write', 38020],
      ]);
    });

    it('folds the slices past maxSlices in input order', () => {
      createComponent({ slices: [...nineSlices].reverse(), preserveOrder: true });

      expect(legendTexts()).toEqual([
        'Zed AI',
        'Cline',
        'Continue.dev',
        'Aider',
        'Windsurf',
        'Other',
      ]);
      expect(seriesData().at(-1)).toMatchObject({ name: 'Other', value: 58 + 34 + 22 + 18 });
    });
  });

  describe('legend placement', () => {
    it('stacks the legend under the donut when placed at the bottom', () => {
      createComponent({ legendPosition: 'bottom' });

      expect(findChartWrapper().element.parentElement.className).toContain('gl-flex-col');
      expect(findLegend().classes()).toContain('gl-flex-wrap');
    });

    it('puts the legend beside the donut by default', () => {
      createComponent();

      expect(findChartWrapper().element.parentElement.className).not.toContain('gl-flex-col');
      expect(findLegend().classes()).toContain('gl-flex-col');
    });
  });

  describe('long labels', () => {
    it('truncates the label and keeps the full text in its title', () => {
      const label = 'business_context_security_guidelines';
      createComponent({ slices: [{ name: 'a', label, value: 1 }] });

      const labelText = findLegendItems().at(0).find('[title]');

      expect(labelText.classes()).toContain('gl-truncate');
      expect(labelText.attributes('title')).toBe(label);
    });
  });

  describe('when loading', () => {
    beforeEach(() => {
      createComponent({ loading: true });
    });

    it('shows a loading icon instead of the chart', () => {
      expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
      expect(findChart().exists()).toBe(false);
      expect(findLegend().exists()).toBe(false);
      expect(findTable().exists()).toBe(false);
    });
  });

  describe('when there is no data', () => {
    beforeEach(() => {
      createComponent({ slices: [{ name: 'read', label: 'Read', value: 0 }] });
    });

    it('shows a single neutral ring with no legend, table or tooltip', () => {
      expect(seriesData()).toEqual([{ value: 1, itemStyle: { color: GL_COLOR_NEUTRAL_400 } }]);
      expect(chartOptions().series[0].silent).toBe(true);
      expect(chartOptions().series[0].padAngle).toBe(0);
      expect(chartOptions().tooltip).toEqual({ show: false });
      expect(findLegend().exists()).toBe(false);
      expect(findTable().exists()).toBe(false);
    });

    it('keeps the centre value and explains the empty chart', () => {
      expect(graphicById('donut-center-value').style.text).toBe('190.1K');
      expect(findEmptyState().text()).toBe('No data available');
    });

    it('shows a custom empty message when given one', () => {
      createComponent({ slices: [], emptyText: 'No tool calls yet.' });

      expect(findEmptyState().text()).toBe('No tool calls yet.');
    });
  });

  describe('accessibility', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names the chart for screen readers without hiding it', () => {
      expect(findChartWrapper().attributes('role')).toBe('img');
      expect(findChartWrapper().attributes('aria-label')).toBe('Tool calls by risk level');
      expect(findChartWrapper().attributes('aria-hidden')).toBeUndefined();
    });

    it('renders a screen-reader list of the same values', () => {
      expect(findTable().classes()).toContain('gl-sr-only');
      expect(
        findTable()
          .findAll('li')
          .wrappers.map((row) => row.text()),
      ).toEqual([
        'Tool calls by risk level',
        '190.1K tool calls',
        'Read: 146,377 (77%)',
        'Write: 38,020 (20%)',
        'Destructive: 5,703 (3%)',
      ]);
    });

    it('hides the decorative legend swatches from screen readers', () => {
      expect(findSwatches().at(0).attributes('aria-hidden')).toBe('true');
    });
  });

  describe('when a label contains HTML characters', () => {
    beforeEach(() => {
      createComponent({ slices: [{ name: 'security', label: 'Security & Compliance', value: 3 }] });
    });

    it('escapes the label in the HTML tooltip', () => {
      expect(chartOptions().tooltip.formatter({ dataIndex: 0 })).toBe(
        'Security &amp; Compliance: 3 (100%)',
      );
    });

    it('reads the label as plain text in the screen-reader list', () => {
      expect(findTable().findAll('li').at(2).text()).toBe('Security & Compliance: 3 (100%)');
    });
  });
});
