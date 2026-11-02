// This spec inspects the console calls it collects, so it must not throw on the first one.
import { shallowMount } from '@vue/test-utils';
import {
  forgetConsoleCalls,
  getConsoleCalls,
  useConsoleWatcherThrowsImmediately,
} from 'helpers/console_watcher';
import VueRenderWarningsComponent from './vue_render_warnings_component.vue';

describe('Vue render warnings', () => {
  useConsoleWatcherThrowsImmediately(false);

  afterEach(() => {
    forgetConsoleCalls();
  });

  describe('when an assertion over a Vue instance fails', () => {
    it('reports the assertion instead of Jest probing the instance', () => {
      const { vm } = shallowMount(VueRenderWarningsComponent);
      const spy = jest.fn();
      spy(vm);

      let message = '';
      try {
        expect(spy).toHaveBeenCalledWith({ neverCalledWithThis: true });
      } catch (error) {
        message = error.message;
      }

      // Jest lays the diff out differently under `--ci`, so assert on its payload.
      expect(message).toContain('neverCalledWithThis');
      expect(message).not.toContain('Unexpected calls to console');
      expect(getConsoleCalls()).toEqual([]);
    });
  });

  describe('when a template reads a property the instance does not define', () => {
    it('reports the warning, naming the property', () => {
      shallowMount(VueRenderWarningsComponent, { propsData: { readUndefinedProperty: true } });

      const [call, ...rest] = getConsoleCalls();

      expect(rest).toEqual([]);
      expect(call.args[0]).toContain('notDefinedAnywhere');
    });
  });

  describe('when a template reads runWithContext', () => {
    it('is ignored, since Pinia expects this property to be missing', () => {
      shallowMount(VueRenderWarningsComponent, { propsData: { readRunWithContext: true } });

      expect(getConsoleCalls()).toEqual([]);
    });
  });
});
