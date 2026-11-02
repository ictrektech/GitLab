import HelpIcon from './help_icon.vue';

export default {
  component: HelpIcon,
  title: 'vue_shared/components/help_icon/help_icon',
};

const Template = (args, { argTypes }) => ({
  components: { HelpIcon },
  props: Object.keys(argTypes),
  template: '<help-icon v-bind="$props" />',
});

export const Default = Template.bind({});
Default.args = {};
