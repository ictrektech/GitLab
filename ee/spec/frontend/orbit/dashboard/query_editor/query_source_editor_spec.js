import { nextTick } from 'vue';
import { KeyCode, KeyMod, languages } from 'monaco-editor';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SourceEditor from '~/vue_shared/components/source_editor.vue';
import QuerySourceEditor from 'ee/orbit/dashboard/query_editor/query_source_editor.vue';
import { normalizeSchema } from 'ee/orbit/dashboard/schema/schema_graph';

describe('QuerySourceEditor', () => {
  let wrapper;
  let instance;
  let ghostContextKey;
  let completions;
  let actions;
  let lineBeforeCursor;

  const ghostQuery = 'MATCH (me:User {id: 74}) RETURN me.username, me.name';

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(QuerySourceEditor, {
      propsData: { value: '', schema: normalizeSchema({}), ghostQuery, ...props },
    });
  };

  const findSourceEditor = () => wrapper.findComponent(SourceEditor);
  const readyEditor = () => findSourceEditor().vm.$emit('editor-ready', { detail: { instance } });
  const findAction = (id) => instance.addAction.mock.calls.find(([action]) => action.id === id)[0];
  const lastGhostDecorations = () => instance.deltaDecorations.mock.calls.at(-1)[1];

  beforeEach(() => {
    ghostContextKey = { set: jest.fn() };
    completions = { dispose: jest.fn() };
    actions = [];
    lineBeforeCursor = '';
    const model = {
      getValueInRange: jest.fn(() => lineBeforeCursor),
      getFullModelRange: jest.fn(() => 'full range'),
      getPositionAt: jest.fn((offset) => ({ lineNumber: 1, column: offset + 1 })),
    };
    instance = {
      addAction: jest.fn(() => {
        const action = { dispose: jest.fn() };
        actions.push(action);
        return action;
      }),
      createContextKey: jest.fn(() => ghostContextKey),
      deltaDecorations: jest.fn(() => ['ghost']),
      getModel: jest.fn(() => model),
      getPosition: jest.fn(() => ({ lineNumber: 1, column: lineBeforeCursor.length + 1 })),
      executeEdits: jest.fn(),
      pushUndoStop: jest.fn(),
      setPosition: jest.fn(),
      trigger: jest.fn(),
      focus: jest.fn(),
    };
    jest.spyOn(languages, 'registerCompletionItemProvider').mockReturnValue(completions);
  });

  describe('when it mounts', () => {
    beforeEach(() => {
      createComponent();
    });

    it('sends ready one tick behind the source editor', async () => {
      readyEditor();
      expect(wrapper.emitted('ready')).toBeUndefined();

      await nextTick();

      expect(wrapper.emitted('ready')).toEqual([[]]);
    });
  });

  describe('when the editor is ready', () => {
    beforeEach(() => {
      createComponent();
      readyEditor();
    });

    it('edits the query as GQL with schema completions', () => {
      expect(findSourceEditor().props()).toMatchObject({
        value: '',
        debounceValue: 0,
        fileName: 'query.gql',
        editorOptions: expect.objectContaining({ language: 'orbit-gql' }),
      });
      expect(languages.registerCompletionItemProvider).toHaveBeenCalledWith(
        'orbit-gql',
        expect.objectContaining({ triggerCharacters: [':', '.'] }),
      );
    });

    it('emits the text the user types', () => {
      findSourceEditor().vm.$emit('input', 'MATCH (p:Project)');

      expect(wrapper.emitted('input')).toEqual([['MATCH (p:Project)']]);
    });

    it('emits run on Cmd or Ctrl and Enter', () => {
      const runAction = findAction('orbit-query-run');
      runAction.run();

      // eslint-disable-next-line no-bitwise -- Monaco combines key codes as bit flags
      expect(runAction.keybindings).toEqual([KeyMod.CtrlCmd | KeyCode.Enter]);
      expect(wrapper.emitted('run')).toHaveLength(1);
    });

    it.each`
      context                   | before          | text              | typed
      ${'an open node'}         | ${'MATCH ('}    | ${'MergeRequest'} | ${'MergeRequest'}
      ${'a word'}               | ${'RETURN mr'}  | ${'mr.title'}     | ${' mr.title'}
      ${'a variable and a dot'} | ${'RETURN mr.'} | ${'mr.title'}     | ${'title'}
    `('inserts text after $context and focuses the editor', ({ before, text, typed }) => {
      lineBeforeCursor = before;
      wrapper.vm.insertText(text);

      expect(instance.trigger).toHaveBeenCalledWith('orbit-query-reference', 'type', {
        text: typed,
      });
      expect(instance.focus).toHaveBeenCalled();
    });

    it('replaces the query as one edit that undo reverts, with the cursor at the end', () => {
      wrapper.vm.replaceText('MATCH (p:Project) RETURN p');

      expect(instance.executeEdits).toHaveBeenCalledWith('orbit-query-editor', [
        { range: 'full range', text: 'MATCH (p:Project) RETURN p' },
      ]);
      expect(instance.pushUndoStop).toHaveBeenCalledTimes(2);
      expect(instance.setPosition).toHaveBeenCalledWith({ lineNumber: 1, column: 27 });
      expect(instance.focus).toHaveBeenCalled();
    });

    describe('when it is destroyed', () => {
      beforeEach(() => {
        wrapper.destroy();
      });

      it('removes the completions and the keyboard actions', () => {
        expect(completions.dispose).toHaveBeenCalled();
        expect(actions.map((action) => action.dispose.mock.calls.length)).toEqual([1, 1]);
      });
    });

    describe('with a ghost query', () => {
      it('shows the ghost query and turns on Tab', () => {
        expect(lastGhostDecorations()).toEqual([
          expect.objectContaining({
            options: expect.objectContaining({
              after: { content: ghostQuery, inlineClassName: '!gl-text-disabled' },
            }),
          }),
        ]);
        expect(ghostContextKey.set).toHaveBeenLastCalledWith(true);
      });

      it('puts the ghost query in the editor on Tab, except in tab focus mode', () => {
        const ghostAction = findAction('orbit-query-use-ghost');
        ghostAction.run();

        expect(ghostAction).toMatchObject({
          keybindings: [KeyCode.Tab],
          precondition: 'orbitQueryShowsGhost && !editorTabMovesFocus',
        });
        expect(instance.executeEdits).toHaveBeenCalledWith('orbit-query-editor', [
          { range: 'full range', text: ghostQuery },
        ]);
      });
    });

    describe('when the ghost query goes away', () => {
      beforeEach(async () => {
        await wrapper.setProps({ value: 'MATCH (p:Project)', ghostQuery: null });
        await nextTick();
      });

      it('hides the ghost query and turns off Tab', () => {
        expect(lastGhostDecorations()).toEqual([]);
        expect(ghostContextKey.set).toHaveBeenLastCalledWith(false);
      });
    });
  });
});
