import { EPIC_COLORS } from '~/work_items/constants';
import SidebarColorPicker from './sidebar_color_picker.vue';

export default {
  component: SidebarColorPicker,
  title: 'sidebar/sidebar_color_picker',
};

const Template = (args, { argTypes }) => ({
  components: { SidebarColorPicker },
  props: Object.keys(argTypes),
  data() {
    return { selectedColor: this.value };
  },
  watch: {
    // Keeps the story in sync when `value` changes via the Controls panel
    value(newValue) {
      this.selectedColor = newValue;
    },
  },
  // Mirrors the v-model binding consumers use, so swatch clicks update the inputs
  template: `
    <sidebar-color-picker
      v-bind="$props"
      :value="selectedColor"
      @input="selectedColor = $event"
    />
  `,
});

export const Default = Template.bind({});
Default.args = {
  value: '#1068bf',
  suggestedColors: EPIC_COLORS,
  errorMessage: '',
  autofocus: false,
};

export const WithoutSuggestedColors = Template.bind({});
WithoutSuggestedColors.args = {
  ...Default.args,
  suggestedColors: [],
};

export const WithErrorMessage = Template.bind({});
WithErrorMessage.args = {
  ...Default.args,
  value: 'not-a-hex-code',
  errorMessage: 'Must be a valid hex code',
};
