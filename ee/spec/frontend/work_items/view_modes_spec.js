import { hasBoardViewMode, viewModeOptions } from 'ee/work_items/view_modes';
import { viewModeOptions as ceViewModeOptions } from '~/work_items/view_modes';
import { VIEW_MODE_BOARD } from '~/work_items/constants';

describe('view modes', () => {
  it('appends the board view mode to the CE ones', () => {
    expect(hasBoardViewMode).toBe(true);
    expect(viewModeOptions.slice(0, -1)).toEqual(ceViewModeOptions);
    expect(viewModeOptions.at(-1)).toEqual({
      value: VIEW_MODE_BOARD,
      text: 'Board',
      props: { icon: 'columns' },
    });
  });
});
