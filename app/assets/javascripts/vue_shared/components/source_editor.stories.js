import SourceEditor from './source_editor.vue';

export default {
  component: SourceEditor,
  title: 'vue_shared/components/source_editor',
};

const Template = (args, { argTypes }) => ({
  components: { SourceEditor },
  props: Object.keys(argTypes),
  template: '<div class="gl-h-48"><source-editor v-bind="$props" /></div>',
});

export const Default = Template.bind({});
Default.args = {
  fileName: 'greeting.js',
  value: `export const greet = (name) => \`Hello, \${name}!\`;

export default greet;
`,
};

export const ReadOnly = Template.bind({});
ReadOnly.args = {
  ...Default.args,
  editorOptions: { readOnly: true },
};

export const DarkTheme = (args, { argTypes }) => ({
  components: { SourceEditor },
  props: Object.keys(argTypes),
  data() {
    return { editorKey: 0 };
  },
  computed: {
    editorProps() {
      const { colorScheme, ...editorProps } = this.$props;
      return editorProps;
    },
  },
  watch: {
    // Monaco reads the scheme when the editor is created, so a new scheme needs a new editor.
    colorScheme: {
      immediate: true,
      handler(scheme) {
        window.gon.user_color_scheme = scheme;
        this.editorKey += 1;
      },
    },
  },
  beforeCreate() {
    this.originalScheme = window.gon.user_color_scheme;
  },
  beforeDestroy() {
    window.gon.user_color_scheme = this.originalScheme;
  },
  template: '<div class="gl-h-48"><source-editor :key="editorKey" v-bind="editorProps" /></div>',
});
DarkTheme.args = {
  ...Default.args,
  colorScheme: 'dark',
};
DarkTheme.argTypes = {
  colorScheme: {
    control: 'select',
    // The theme names from ~/ide/lib/themes, which vue_shared can't import.
    options: ['white', 'dark', 'solarized-light', 'solarized-dark', 'monokai', 'dracula', 'none'],
  },
};
DarkTheme.parameters = {
  docs: {
    // Monaco themes apply to every editor on the page, so the docs page renders this story in its own iframe.
    story: { inline: false, iframeHeight: 240 },
  },
};
