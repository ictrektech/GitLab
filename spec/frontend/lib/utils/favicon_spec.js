import { FaviconOverlayManager } from '@gitlab/favicon-overlay';
import * as faviconUtils from '~/lib/utils/favicon';

jest.mock('@gitlab/favicon-overlay');

describe('~/lib/utils/favicon', () => {
  afterEach(() => {
    faviconUtils.clearMemoizeCache();
  });

  describe.each`
    fnName                 | fn                                | managerFn                                    | args
    ${'setFaviconOverlay'} | ${faviconUtils.setFaviconOverlay} | ${FaviconOverlayManager.setFaviconOverlay}   | ${['test']}
    ${'resetFavicon'}      | ${faviconUtils.resetFavicon}      | ${FaviconOverlayManager.resetFaviconOverlay} | ${[]}
  `('$fnName', ({ fn, managerFn, args }) => {
    const call = () => fn(...args);

    it('initializes only once when called', async () => {
      expect(FaviconOverlayManager.initialize).not.toHaveBeenCalled();

      // Call twice so we can make sure initialize is only called once
      await call();
      await call();

      expect(FaviconOverlayManager.initialize).toHaveBeenCalledWith({
        faviconSelector: '#favicon',
      });
      expect(FaviconOverlayManager.initialize).toHaveBeenCalledTimes(1);
    });

    it('passes call to manager', async () => {
      expect(managerFn).not.toHaveBeenCalled();

      await call();

      expect(managerFn).toHaveBeenCalledWith(...args);
    });
  });
});
