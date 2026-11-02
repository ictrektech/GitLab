import { EDITOR_READY_EVENT } from '~/editor/constants';
import { CiSchemaExtension } from '~/editor/extensions/source_editor_ci_schema_ext';
import SourceEditor from '~/vue_shared/components/source_editor.vue';

export default {
  component: SourceEditor,
  title: 'editor/source_editor',
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

export const CiYamlWithSchema = (args, { argTypes }) => ({
  components: { SourceEditor },
  props: Object.keys(argTypes),
  methods: {
    registerCiSchema({ detail: { instance } }) {
      instance.use({ definition: CiSchemaExtension });
      instance.registerCiSchema();
    },
  },
  readyEvent: EDITOR_READY_EVENT,
  template: `<div class="gl-h-48">
    <source-editor v-bind="$props" @[$options.readyEvent]="registerCiSchema" />
  </div>`,
});
CiYamlWithSchema.args = {
  fileName: '.gitlab-ci.yml',
  value: `build:
  stage: build
  script: make
  when: sometimes
`,
};
