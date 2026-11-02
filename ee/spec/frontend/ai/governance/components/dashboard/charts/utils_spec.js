import {
  foldSlices,
  integerPercentages,
  sliceColorMap,
} from 'ee/ai/governance/components/dashboard/charts/utils';
import { DONUT_SLICE_LIMIT } from 'ee/ai/governance/components/dashboard/charts/constants';

describe('AI governance donut chart utils', () => {
  describe('foldSlices', () => {
    it('orders slices by value descending', () => {
      const folded = foldSlices(
        [
          { name: 'b', value: 2 },
          { name: 'a', value: 9 },
        ],
        5,
      );

      expect(folded.map(({ name }) => name)).toEqual(['a', 'b']);
    });

    it('breaks ties on the slice name so the order is deterministic', () => {
      const folded = foldSlices(
        [
          { name: 'zed', value: 4 },
          { name: 'aider', value: 4 },
          { name: 'cline', value: 4 },
        ],
        5,
      );

      expect(folded.map(({ name }) => name)).toEqual(['aider', 'cline', 'zed']);
    });

    it('drops empty and non-numeric slices', () => {
      const folded = foldSlices(
        [
          { name: 'a', value: 3 },
          { name: 'b', value: 0 },
          { name: 'c', value: -1 },
          { name: 'd', value: Number.NaN },
        ],
        5,
      );

      expect(folded.map(({ name }) => name)).toEqual(['a']);
    });

    it('defaults the label to the slice name', () => {
      expect(foldSlices([{ name: 'claude-code', value: 1 }], 5)[0].label).toBe('claude-code');
    });

    describe('when there are more slices than maxSlices', () => {
      const nineSlices = Array.from({ length: 9 }, (unused, index) => ({
        name: `agent-${index}`,
        value: 9 - index,
      }));

      it('keeps maxSlices slices and folds the rest into one "Other" slice', () => {
        const folded = foldSlices(nineSlices, 5);

        expect(folded).toHaveLength(6);
        expect(folded.map(({ label }) => label)).toEqual([
          'agent-0',
          'agent-1',
          'agent-2',
          'agent-3',
          'agent-4',
          'Other',
        ]);
      });

      it('sums the folded slices so the parts still add up to the whole', () => {
        const folded = foldSlices(nineSlices, 5);

        expect(folded[5].value).toBe(4 + 3 + 2 + 1);
        expect(folded.reduce((total, { value }) => total + value, 0)).toBe(45);
      });
    });
    describe('with preserveOrder', () => {
      it('keeps the input order', () => {
        const folded = foldSlices(
          [
            { name: 'b', value: 2 },
            { name: 'a', value: 9 },
            { name: 'c', value: 5 },
          ],
          5,
          { preserveOrder: true },
        );

        expect(folded.map(({ name }) => name)).toEqual(['b', 'a', 'c']);
      });

      it('still drops empty slices', () => {
        const folded = foldSlices(
          [
            { name: 'a', value: 0 },
            { name: 'b', value: 3 },
            { name: 'c', value: Number.NaN },
            { name: 'd', value: 1 },
          ],
          5,
          { preserveOrder: true },
        );

        expect(folded.map(({ name }) => name)).toEqual(['b', 'd']);
      });

      it('keeps the first maxSlices in input order and folds the rest', () => {
        const folded = foldSlices(
          [
            { name: 'a', value: 1 },
            { name: 'b', value: 2 },
            { name: 'c', value: 30 },
            { name: 'd', value: 40 },
          ],
          2,
          { preserveOrder: true },
        );

        expect(folded.map(({ name, value }) => [name, value])).toEqual([
          ['a', 1],
          ['b', 2],
          ['donut-other', 70],
        ]);
      });
    });
  });

  describe('integerPercentages', () => {
    it.each`
      values                   | expected
      ${[1, 1, 1]}             | ${[34, 33, 33]}
      ${[1, 1, 1, 1, 1, 1]}    | ${[17, 17, 17, 17, 16, 16]}
      ${[146377, 38020, 5703]} | ${[77, 20, 3]}
      ${[7]}                   | ${[100]}
    `('turns $values into $expected, totalling 100', ({ values, expected }) => {
      const percentages = integerPercentages(values);

      expect(percentages).toEqual(expected);
      expect(percentages.reduce((total, value) => total + value, 0)).toBe(100);
    });

    it('returns zeroes when the total is zero', () => {
      expect(integerPercentages([0, 0])).toEqual([0, 0]);
    });
  });

  describe('sliceColorMap', () => {
    it('assigns palette colours in fixed order over alphabetical names', () => {
      expect(sliceColorMap(['orange-user', 'blue-user'])).toEqual({
        'blue-user': '#617ae2',
        'orange-user': '#b14f18',
      });
    });

    it('colours more slices than the readability default without repeating', () => {
      const names = Array.from({ length: 12 }, (unused, index) => `agent-${index}`);
      const colors = Object.values(sliceColorMap(names));

      expect(new Set(colors).size).toBe(12);
    });

    it('wraps around once the palette is exhausted', () => {
      // Zero-padded so the alphabetical ordering matches the numeric one.
      const name = (index) => `agent-${String(index).padStart(2, '0')}`;
      const colors = sliceColorMap(
        Array.from({ length: DONUT_SLICE_LIMIT + 1 }, (u, i) => name(i)),
      );

      expect(colors[name(DONUT_SLICE_LIMIT)]).toBe(colors[name(0)]);
    });

    describe('in dark mode', () => {
      beforeEach(() => {
        document.documentElement.classList.add('gl-dark');
      });

      afterEach(() => {
        document.documentElement.classList.remove('gl-dark');
      });

      // Index 0 is the same colour in both palettes, so only a later index
      // can show which palette was picked.
      it('takes colours from the dark palette', () => {
        expect(sliceColorMap(['orange-user', 'blue-user'])).toEqual({
          'blue-user': '#617ae2',
          'orange-user': '#e07e41',
        });
      });
    });

    it('keeps every hue when the slices are re-ranked', () => {
      const ranking = sliceColorMap(['aider', 'cline', 'zed']);
      const reversedRanking = sliceColorMap(['zed', 'cline', 'aider']);

      expect(reversedRanking).toEqual(ranking);
    });

    it('keeps explicit hues when a slice is filtered out', () => {
      const colors = { read: '#111111', write: '#222222', destructive: '#333333' };

      expect(sliceColorMap(['read', 'destructive'], colors)).toEqual({
        read: '#111111',
        destructive: '#333333',
      });
    });

    it('prefers an explicit colour for a name', () => {
      expect(sliceColorMap(['read', 'write'], { read: '#abcdef' })).toEqual({
        read: '#abcdef',
        write: '#617ae2',
      });
    });
  });
});
