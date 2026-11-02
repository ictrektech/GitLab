import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import { maybeStartScreensaver } from 'ee/ai/easter_eggs/avatar_screensaver';

describe('avatar_screensaver easter egg', () => {
  const { innerWidth } = window;
  const addMessage = jest.fn();
  let original;

  const findScrim = () => document.querySelector('[aria-hidden="true"].gl-fixed');
  const findBouncingAvatar = () => findScrim()?.firstElementChild;
  const finishFadeIn = () => Element.prototype.animate.mock.results.at(-1).value.onfinish();
  const runFrame = (now) => window.requestAnimationFrame.mock.calls.at(-1)[0](now);
  const dispatch = (type, props = {}) =>
    window.dispatchEvent(Object.assign(new Event(type), props));

  beforeEach(() => {
    window.gon.dot_com = true;
    Element.prototype.animate = jest.fn(() => ({ cancel: jest.fn(), onfinish: null }));
    jest.spyOn(window, 'requestAnimationFrame').mockReturnValue(1);
    jest.spyOn(window, 'cancelAnimationFrame');

    setHTMLFixture('<span data-testid="user-avatar-content">CL</span>');
    original = document.querySelector('[data-testid="user-avatar-content"]');
    jest
      .spyOn(original, 'getBoundingClientRect')
      .mockReturnValue({ left: 0, top: 10, width: 24, height: 24 });
  });

  afterEach(() => {
    dispatch('keydown');
    delete Element.prototype.animate;
    window.innerWidth = innerWidth;
    resetHTMLFixture();
  });

  it.each([
    'what is a merge request',
    'screensaver please',
    'do a barrel roll',
    '',
    null,
    undefined,
  ])('ignores %p', (prompt) => {
    expect(maybeStartScreensaver(prompt, addMessage)).toBe(false);
    expect(findScrim()).toBeNull();
    expect(addMessage).not.toHaveBeenCalled();
  });

  it('ignores the command outside GitLab.com', () => {
    window.gon.dot_com = false;

    expect(maybeStartScreensaver('screensaver', addMessage)).toBe(false);
    expect(findScrim()).toBeNull();
    expect(addMessage).not.toHaveBeenCalled();
  });

  it.each(['screensaver', '  Screensaver  ', 'SCREENSAVER'])(
    'starts the screensaver for %p',
    (prompt) => {
      expect(maybeStartScreensaver(prompt, addMessage)).toBe(true);
      expect(findBouncingAvatar().textContent).toBe('CL');
      expect(findBouncingAvatar().dataset.testid).toBeUndefined();
      expect(findBouncingAvatar().style.transform).toBe('translate3d(0px, 10px, 0)');
      expect(addMessage).not.toHaveBeenCalled();
    },
  );

  it('hides the header avatar and starts moving once the fade-in finishes', () => {
    maybeStartScreensaver('screensaver', addMessage);

    expect(original.style.visibility).toBe('');
    expect(window.requestAnimationFrame).not.toHaveBeenCalled();

    finishFadeIn();

    expect(original.style.visibility).toBe('hidden');
    expect(window.requestAnimationFrame).toHaveBeenCalledTimes(1);
  });

  it('shifts the hue when the avatar bounces off an edge', () => {
    maybeStartScreensaver('screensaver', addMessage);
    finishFadeIn();

    runFrame(1000);

    expect(findBouncingAvatar().style.filter).toBe('hue-rotate(60deg)');
  });

  it('moves the avatar on each frame', () => {
    original.getBoundingClientRect.mockReturnValue({ left: 100, top: 100, width: 24, height: 24 });
    maybeStartScreensaver('screensaver', addMessage);
    finishFadeIn();

    runFrame(1000);
    runFrame(1020);

    expect(findBouncingAvatar().style.transform).toBe('translate3d(97px, 103px, 0)');
    expect(findBouncingAvatar().style.filter).toBe('');
  });

  it('does not start a second screensaver while one is running', () => {
    maybeStartScreensaver('screensaver', addMessage);

    expect(maybeStartScreensaver('screensaver', addMessage)).toBe(true);
    expect(document.querySelectorAll('[aria-hidden="true"].gl-fixed')).toHaveLength(1);
  });

  it.each(['pointerdown', 'keydown', 'wheel', 'touchstart', 'scroll', 'resize'])(
    'stops on %s',
    (type) => {
      maybeStartScreensaver('screensaver', addMessage);
      finishFadeIn();

      dispatch(type);

      expect(findScrim()).toBeNull();
      expect(original.style.visibility).toBe('');
      expect(window.cancelAnimationFrame).toHaveBeenCalledWith(1);
    },
  );

  it('ignores a pointermove without movement', () => {
    maybeStartScreensaver('screensaver', addMessage);

    dispatch('pointermove', { movementX: 0, movementY: 0 });

    expect(findScrim()).not.toBeNull();
  });

  it('stops on a pointermove with movement', () => {
    maybeStartScreensaver('screensaver', addMessage);

    dispatch('pointermove', { movementX: 1, movementY: 0 });

    expect(findScrim()).toBeNull();
  });

  it('can start again after stopping', () => {
    maybeStartScreensaver('screensaver', addMessage);
    dispatch('keydown');

    maybeStartScreensaver('screensaver', addMessage);

    expect(findScrim()).not.toBeNull();
  });

  describe.each([
    [
      'the user prefers reduced motion',
      () => jest.spyOn(window, 'matchMedia').mockReturnValue({ matches: true }),
    ],
    [
      'the viewport is narrow',
      () => {
        window.innerWidth = 500;
      },
    ],
    ['the header avatar is missing', () => resetHTMLFixture()],
  ])('when %s', (_, setup) => {
    beforeEach(setup);

    it('replies in chat instead of starting the screensaver', () => {
      expect(maybeStartScreensaver('screensaver', addMessage)).toBe(true);
      expect(findScrim()).toBeNull();
      expect(addMessage.mock.calls).toEqual([
        [expect.objectContaining({ role: 'user', content: 'screensaver' })],
        [
          expect.objectContaining({
            role: 'assistant',
            content:
              "I can't start the screensaver easter egg with your current display or accessibility settings.",
          }),
        ],
      ]);
    });
  });
});
