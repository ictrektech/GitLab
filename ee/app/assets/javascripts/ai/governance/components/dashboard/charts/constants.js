import { GL_COLOR_NEUTRAL_400 } from '@gitlab/ui/src/tokens/build/js/tokens';
import { colorPaletteDefault } from '@gitlab/ui/src/utils/charts/theme';

export const DONUT_OTHER_COLOR = GL_COLOR_NEUTRAL_400;

// Reserved slice name for the folded remainder, hyphenated so it cannot
// collide with a dimension value coming from the API.
export const DONUT_OTHER_NAME = 'donut-other';

// A readability default, not a palette ceiling: the categorical palette colours
// up to DONUT_SLICE_LIMIT slices, but a donut gets crowded well before that.
export const DONUT_MAX_SLICES = 5;

export const DONUT_SLICE_LIMIT = colorPaletteDefault.length;

export const LEGEND_POSITION_RIGHT = 'right';
export const LEGEND_POSITION_BOTTOM = 'bottom';
export const LEGEND_POSITIONS = [LEGEND_POSITION_RIGHT, LEGEND_POSITION_BOTTOM];
