import { serialize, builders, roundTrip } from '../../serialization_utils';

const { paragraph, footnoteDefinition, footnoteReference } = builders;

// What the markdown API renders for
// "a[^my-note] b[^😄] c[^x-1]\n\n[^my-note]: one\n[^😄]: two\n[^x-1]: three".
const FOOTNOTE_NAMES_HTML = `<p dir="auto">a<sup class="footnote-ref"><a href="#fn-my-note-42" id="fnref-my-note-42" data-footnote-ref="">1</a></sup> b<sup class="footnote-ref"><a href="#fn-%F0%9F%98%84-42" id="fnref-%F0%9F%98%84-42" data-footnote-ref="">2</a></sup> c<sup class="footnote-ref"><a href="#fn-x-1-42" id="fnref-x-1-42" data-footnote-ref="">3</a></sup></p>
<section data-footnotes="" class="footnotes">
<ol>
<li id="fn-my-note-42">
<p>one <a href="#fnref-my-note-42" data-footnote-backref="" data-footnote-backref-idx="1" aria-label="Back to reference 1" title="Back to reference 1" class="footnote-backref">↩</a></p>
</li>
<li id="fn-%F0%9F%98%84-42">
<p>two <a href="#fnref-%F0%9F%98%84-42" data-footnote-backref="" data-footnote-backref-idx="2" aria-label="Back to reference 2" title="Back to reference 2" class="footnote-backref">↩</a></p>
</li>
<li id="fn-x-1-42">
<p>three <a href="#fnref-x-1-42" data-footnote-backref="" data-footnote-backref-idx="3" aria-label="Back to reference 3" title="Back to reference 3" class="footnote-backref">↩</a></p>
</li>
</ol>
</section>`;

// The HTML for "a[^1] b[^1]\n\n[^1]: note" once FootnoteFilter links every
// reference to the footnote: the second reference has the id fnref-1-2-42.
const FOOTNOTE_REFERENCED_TWICE_HTML = `<p dir="auto">a<sup class="footnote-ref"><a href="#fn-1-42" id="fnref-1-42" data-footnote-ref="">1</a></sup> b<sup class="footnote-ref"><a href="#fn-1-42" id="fnref-1-2-42" data-footnote-ref="">1</a></sup></p>
<section data-footnotes="" class="footnotes">
<ol>
<li id="fn-1-42">
<p>note <a href="#fnref-1-42" data-footnote-backref="" data-footnote-backref-idx="1" aria-label="Back to reference 1" title="Back to reference 1" class="footnote-backref">↩</a> <a href="#fnref-1-2-42" data-footnote-backref="" data-footnote-backref-idx="1-2" aria-label="Back to reference 1-2" title="Back to reference 1-2" class="footnote-backref">↩<sup>2</sup></a></p>
</li>
</ol>
</section>`;

it('correctly serializes footnotes', () => {
  expect(
    serialize(
      paragraph('Oranges are orange ', footnoteReference({ label: '1', identifier: '1' })),
      footnoteDefinition({ label: '1', identifier: '1' }, 'Oranges are fruits'),
    ),
  ).toBe(
    `
Oranges are orange [^1]

[^1]: Oranges are fruits
`.trimLeft(),
  );
});

it('round-trips footnote names with hyphens, encoded characters or trailing digits', async () => {
  expect(await roundTrip(FOOTNOTE_NAMES_HTML)).toBe(
    'a[^my-note] b[^😄] c[^x-1]\n\n[^my-note]: one\n\n[^😄]: two\n\n[^x-1]: three\n',
  );
});

it('round-trips a footnote referenced twice', async () => {
  expect(await roundTrip(FOOTNOTE_REFERENCED_TWICE_HTML)).toBe('a[^1] b[^1]\n\n[^1]: note\n');
});
