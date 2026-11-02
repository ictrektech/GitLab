import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { RuleTester } from 'eslint';
import { afterAll } from 'vitest';
import { noAsyncComponentWithModel } from '../../../../../tooling/eslint-config/eslint-local-rules/no_async_component_with_model';

const dir = mkdtempSync(path.join(tmpdir(), 'no-async-component-with-model-'));
const filename = path.join(dir, 'parent.js');

afterAll(() => {
  rmSync(dir, { recursive: true, force: true });
});

writeFileSync(
  path.join(dir, 'with_model.vue'),
  `<script>
export default {
  model: { prop: 'checked', event: 'toggle' },
  props: { checked: Boolean },
};
</script>`,
);
writeFileSync(
  path.join(dir, 'with_model_reference.vue'),
  `<script>
import Other from './with_model.vue';

export default {
  model: Other.model,
  props: Other.props,
};
</script>`,
);
writeFileSync(
  path.join(dir, 'without_model.vue'),
  `<script>
export default {
  props: { checked: Boolean },
  computed: {
    options() {
      return { nested: { model: {} } };
    },
  },
};
</script>`,
);

writeFileSync(
  path.join(dir, 'unparsable.vue'),
  `<script>
export default {
</script>`,
);

const ruleTester = new RuleTester({
  languageOptions: { ecmaVersion: 2022, sourceType: 'module' },
});

ruleTester.run('no-async-component-with-model', noAsyncComponentWithModel, {
  valid: [
    { filename, code: `const Child = () => import('./without_model.vue');` },
    { filename, code: `import Child from './with_model.vue';` },
    { filename, code: `const Child = () => import('./missing.vue');` },
    { filename, code: `const Child = (name) => import(\`./\${name}.vue\`);` },
    { filename, code: `const Child = () => import('./unparsable.vue');` },
  ],
  invalid: [
    {
      filename,
      code: `const Child = () => import('./with_model.vue');`,
      errors: [{ messageId: 'asyncModel' }],
    },
    {
      filename,
      code: `const Child = defineAsyncComponent(() => import(/* webpackChunkName: 'x' */ './with_model.vue'));`,
      errors: [{ messageId: 'asyncModel' }],
    },
    {
      filename,
      code: 'const Child = () => import(`./with_model.vue`);',
      errors: [{ messageId: 'asyncModel' }],
    },
    {
      filename,
      code: `const Child = () => import('./with_model_reference.vue');`,
      errors: [{ messageId: 'asyncModel' }],
    },
  ],
});
