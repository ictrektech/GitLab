import { RuleTester } from 'eslint';
import { noUnsuppliedFactoryParam } from '../../../../../tooling/eslint-config/eslint-local-rules/no_unsupplied_factory_param.mjs';

const ruleTester = new RuleTester({
  languageOptions: {
    ecmaVersion: 2022,
    sourceType: 'module',
  },
});

const lines = (...parts) => parts.join('\n');

ruleTester.run('no-unsupplied-factory-param', noUnsuppliedFactoryParam, {
  valid: [
    {
      name: 'stays silent when a call site supplies the key',
      code: lines(
        'const createComponent = ({ props = {} } = {}) => {',
        '  mount(C, { propsData: { ...defaultProps, ...props } });',
        '};',
        'createComponent();',
        'createComponent({ props: { a: 1 } });',
      ),
    },
    {
      name: 'stays silent when the supplying call spans several lines',
      code: lines(
        'const createComponent = ({ props = {} } = {}) => {',
        '  mount(C, { propsData: { ...props } });',
        '};',
        'createComponent({',
        '  props: {',
        '    a: 1,',
        '  },',
        '});',
      ),
    },
    {
      name: 'stays silent when an object key shares the parameter name, because a key is not a read',
      code: lines(
        'const createComponent = ({ provide = {} } = {}) => {',
        '  mount(C, { provide: defaultProvide });',
        '};',
        'createComponent();',
      ),
    },
    {
      name: 'stays silent when another parameter default reads the key',
      code: lines(
        'const createComponent = ({ props = {}, resp = build(props) } = {}) => {',
        '  mount(C, { propsData: { ...props }, resp });',
        '};',
        'createComponent();',
      ),
    },
    {
      name: 'stays silent when the parameter is read twice, so the spread is not the only read',
      code: lines(
        'const createComponent = ({ props = {} } = {}) => {',
        '  log(props);',
        '  mount(C, { propsData: { ...props } });',
        '};',
        'createComponent();',
      ),
    },
    {
      name: 'stays silent when the parameter is a plain key/value, because removing it drops a key',
      code: lines(
        'const createComponent = ({ stubs = {} } = {}) => {',
        '  mount(C, { stubs });',
        '};',
        'createComponent();',
      ),
    },
    {
      name: 'stays silent when the default is not an empty object',
      code: lines(
        'const createComponent = ({ props = { a: 1 } } = {}) => {',
        '  mount(C, { propsData: { ...props } });',
        '};',
        'createComponent();',
      ),
    },
    {
      name: 'stays silent when the spread goes into an array, not an object literal',
      code: lines(
        'const createComponent = ({ items = {} } = {}) => {',
        '  mount(C, { propsData: { items: [...items] } });',
        '};',
        'createComponent();',
      ),
    },
    {
      name: 'stays silent when the factory is exported, so a call may live in another file',
      code: lines(
        'export const createComponent = ({ props = {} } = {}) => {',
        '  mount(C, { propsData: { ...props } });',
        '};',
        'createComponent();',
      ),
    },
    {
      name: 'stays silent when the factory is passed as a value, so the arguments cannot be read',
      code: lines(
        'const createComponent = ({ props = {} } = {}) => {',
        '  mount(C, { propsData: { ...props } });',
        '};',
        'beforeEach(createComponent);',
      ),
    },
    {
      name: 'stays silent when a call passes a non-literal argument, which hides the keys',
      code: lines(
        'const createComponent = ({ props = {} } = {}) => {',
        '  mount(C, { propsData: { ...props } });',
        '};',
        'createComponent(options);',
      ),
    },
    {
      name: 'stays silent when a call passes a spread argument, which hides the keys',
      code: lines(
        'const createComponent = ({ props = {} } = {}) => {',
        '  mount(C, { propsData: { ...props } });',
        '};',
        'createComponent({ ...options });',
      ),
    },
    {
      name: 'stays silent when a call passes a computed key, which hides the name',
      code: lines(
        'const createComponent = ({ props = {} } = {}) => {',
        '  mount(C, { propsData: { ...props } });',
        '};',
        'createComponent({ [key]: 1 });',
      ),
    },
    {
      name: 'stays silent when the factory is never called, which no-unused-vars reports instead',
      code: lines(
        'const createComponent = ({ props = {} } = {}) => {',
        '  mount(C, { propsData: { ...props } });',
        '};',
      ),
    },
    {
      name: 'stays silent on renamed destructuring when the key is supplied',
      code: lines(
        'const createComponent = ({ props: extra = {} } = {}) => {',
        '  mount(C, { propsData: { ...extra } });',
        '};',
        'createComponent({ props: { a: 1 } });',
      ),
    },
    {
      name: 'stays silent when the parameter is reassigned, so the default is not provable',
      code: lines(
        'const createComponent = ({ props = {} } = {}) => {',
        '  props = buildProps();',
        '  mount(C, { propsData: { ...props } });',
        '};',
        'createComponent();',
      ),
    },
  ],

  invalid: [
    {
      name: 'reports the canonical shape',
      code: lines(
        'const createComponent = ({ props = {} } = {}) => {',
        '  mount(C, { propsData: { ...defaultProps, ...props } });',
        '};',
        'createComponent();',
      ),
      errors: [
        {
          messageId: 'unsuppliedFactoryParam',
          data: { name: 'props', factory: 'createComponent' },
        },
      ],
    },
    {
      name: 'reports a parameter when the destructure itself has no default',
      code: lines(
        'const createWrapper = ({ item, props = {} }) => {',
        '  mount(C, { propsData: { item, ...props } });',
        '};',
        'createWrapper({ item: 1 });',
      ),
      errors: [
        { messageId: 'unsuppliedFactoryParam', data: { name: 'props', factory: 'createWrapper' } },
      ],
    },
    {
      name: 'reports two dead parameters in one factory',
      code: lines(
        'const createComponent = ({ props = {}, provide = {} } = {}) => {',
        '  mount(C, { propsData: { ...props }, provide: { ...provide } });',
        '};',
        'createComponent();',
      ),
      errors: [
        {
          messageId: 'unsuppliedFactoryParam',
          data: { name: 'props', factory: 'createComponent' },
        },
        {
          messageId: 'unsuppliedFactoryParam',
          data: { name: 'provide', factory: 'createComponent' },
        },
      ],
    },
    {
      name: 'reports only the unsupplied one of two parameters',
      code: lines(
        'const factory = ({ extraProps = {}, mockRoute = {} } = {}) => {',
        '  mount(C, { propsData: { ...extraProps }, mocks: { $route: { ...mockRoute } } });',
        '};',
        'factory({ extraProps: { a: 1 } });',
      ),
      errors: [
        { messageId: 'unsuppliedFactoryParam', data: { name: 'mockRoute', factory: 'factory' } },
      ],
    },
    {
      name: 'reports a factory written as a function declaration',
      code: lines(
        'function createComponent({ provide = {} } = {}) {',
        '  mount(C, { provide: { ...defaultProvide, ...provide } });',
        '}',
        'createComponent();',
      ),
      errors: [
        {
          messageId: 'unsuppliedFactoryParam',
          data: { name: 'provide', factory: 'createComponent' },
        },
      ],
    },
    {
      name: 'reports renamed destructuring when the key is not supplied',
      code: lines(
        'const createComponent = ({ props: extra = {} } = {}) => {',
        '  mount(C, { propsData: { ...extra } });',
        '};',
        'createComponent();',
      ),
      errors: [
        {
          messageId: 'unsuppliedFactoryParam',
          data: { name: 'props', factory: 'createComponent' },
        },
      ],
    },
  ],
});
