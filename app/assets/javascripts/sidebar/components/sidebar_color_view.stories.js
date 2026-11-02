import SidebarColorView from './sidebar_color_view.vue';

export default {
  component: SidebarColorView,
  title: 'sidebar/sidebar_color_view',
};

const Template = (args, { argTypes }) => ({
  components: { SidebarColorView },
  props: Object.keys(argTypes),
  template: '<sidebar-color-view v-bind="$props" />',
});

export const Default = Template.bind({});
Default.args = {
  color: '#217645',
  colorName: 'Forest green',
};

export const WithoutColorName = Template.bind({});
WithoutColorName.args = {
  color: '#217645',
  colorName: '',
};
