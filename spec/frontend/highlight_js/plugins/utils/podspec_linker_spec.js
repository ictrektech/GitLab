import hljs from 'highlight.js/lib/core';
import ruby from 'highlight.js/lib/languages/ruby';
import wrapChildNodes from '~/highlight_js/plugins/wrap_child_nodes';
import wrapBidiChars from '~/highlight_js/plugins/wrap_bidi_chars';
import podspecLinker from '~/highlight_js/plugins/utils/podspec_linker';

hljs.registerLanguage('ruby', ruby);
hljs.addPlugin({ 'after:highlight': wrapChildNodes });
hljs.addPlugin({ 'after:highlight': wrapBidiChars });

describe('Highlight.js plugin for linking podspec dependencies', () => {
  const link = (text, href) =>
    `<a href="${href}" target="_blank" rel="nofollow noreferrer noopener">${text}</a>`;

  it('links dependencies to their page on cocoapods.org', () => {
    const inputValue =
      '<span class="">  s.dependency </span><span class="hljs-string">&#39;AFNetworking&#39;</span><span class="">, </span><span class="hljs-string">&#39;~&gt; 3.0&#39;</span>';
    const outputValue = `<span class="">  s.dependency </span><span class="hljs-string">&#39;${link('AFNetworking', 'https://cocoapods.org/pods/AFNetworking')}&#39;</span><span class="">, </span><span class="hljs-string">&#39;~&gt; 3.0&#39;</span>`;

    expect(podspecLinker({ value: inputValue })).toBe(outputValue);
  });

  it('supports double quotes and links subspecs to their parent pod', () => {
    const inputValue =
      '<span class="">  s.dependency </span><span class="hljs-string">&quot;SDWebImage/WebP&quot;</span>';
    const outputValue = `<span class="">  s.dependency </span><span class="hljs-string">&quot;${link('SDWebImage/WebP', 'https://cocoapods.org/pods/SDWebImage')}&quot;</span>`;

    expect(podspecLinker({ value: inputValue })).toBe(outputValue);
  });

  it('links a parenthesised call and one separated by a tab', () => {
    const inputValue =
      '<span class="">  s.dependency</span><span class="">(</span><span class="hljs-string">&#39;SDWebImage/WebP&#39;</span><span class="">)</span>\n' +
      '<span class="">  s.dependency\t</span><span class="hljs-string">&#39;Masonry&#39;</span>';
    const outputValue =
      `<span class="">  s.dependency</span><span class="">(</span><span class="hljs-string">&#39;${link('SDWebImage/WebP', 'https://cocoapods.org/pods/SDWebImage')}&#39;</span><span class="">)</span>\n` +
      `<span class="">  s.dependency\t</span><span class="hljs-string">&#39;${link('Masonry', 'https://cocoapods.org/pods/Masonry')}&#39;</span>`;

    expect(podspecLinker({ value: inputValue })).toBe(outputValue);
  });

  it('links the license to choosealicense.com', () => {
    const inputValue =
      '<span class="">  s.license      </span><span class="">= </span><span class="hljs-string">&#39;MIT&#39;</span>';
    const outputValue = `<span class="">  s.license      </span><span class="">= </span><span class="hljs-string">&#39;${link('MIT', 'https://choosealicense.com/licenses/mit/')}&#39;</span>`;

    expect(podspecLinker({ value: inputValue })).toBe(outputValue);
  });

  it('links the license given as the type key of a hash', () => {
    const inputValue =
      '<span class="">  s.license </span><span class="">= </span><span class="">{ </span><span class="hljs-symbol"><span class="hljs-symbol">:</span><span class="hljs-symbol">type</span></span><span class=""> </span><span class="">=</span><span class="">&gt; </span><span class="hljs-string">&#39;GPL-3.0&#39;</span><span class=""> }</span>\n' +
      '<span class="">  s.license </span><span class="">= </span><span class="">{ </span><span class="hljs-symbol">type:</span><span class=""> </span><span class="hljs-string">&#39;Apache-2.0&#39;</span><span class=""> }</span>';
    const outputValue =
      `<span class="">  s.license </span><span class="">= </span><span class="">{ </span><span class="hljs-symbol"><span class="hljs-symbol">:</span><span class="hljs-symbol">type</span></span><span class=""> </span><span class="">=</span><span class="">&gt; </span><span class="hljs-string">&#39;${link('GPL-3.0', 'https://choosealicense.com/licenses/gpl-3.0/')}&#39;</span><span class=""> }</span>\n` +
      `<span class="">  s.license </span><span class="">= </span><span class="">{ </span><span class="hljs-symbol">type:</span><span class=""> </span><span class="hljs-string">&#39;${link('Apache-2.0', 'https://choosealicense.com/licenses/apache-2.0/')}&#39;</span><span class=""> }</span>`;

    expect(podspecLinker({ value: inputValue })).toBe(outputValue);
  });

  it('links URL strings such as the homepage and the git source', () => {
    const inputValue =
      '<span class="">  s.homepage     </span><span class="">= </span><span class="hljs-string">&#39;https://github.com/tonymillion/Reachability&#39;</span>\n' +
      '<span class="hljs-symbol">git</span></span><span class=""> </span><span class="">=</span><span class="">&gt; </span><span class="hljs-string">&#39;https://github.com/tonymillion/Reachability.git&#39;</span>';
    const outputValue =
      `<span class="">  s.homepage     </span><span class="">= </span><span class="hljs-string">&#39;${link('https://github.com/tonymillion/Reachability', 'https://github.com/tonymillion/Reachability')}&#39;</span>\n` +
      `<span class="hljs-symbol">git</span></span><span class=""> </span><span class="">=</span><span class="">&gt; </span><span class="hljs-string">&#39;${link('https://github.com/tonymillion/Reachability.git', 'https://github.com/tonymillion/Reachability.git')}&#39;</span>`;

    expect(podspecLinker({ value: inputValue })).toBe(outputValue);
  });

  it('keeps an escaped query string inside the URL', () => {
    const escapedUrl = 'https://example.com/a?x=1&amp;y=2';
    const inputValue = `<span class="">  s.homepage </span><span class="">= </span><span class="hljs-string">&#39;${escapedUrl}&#39;</span>`;
    const outputValue = `<span class="">  s.homepage </span><span class="">= </span><span class="hljs-string">&#39;${link(escapedUrl, escapedUrl)}&#39;</span>`;

    expect(podspecLinker({ value: inputValue })).toBe(outputValue);
  });

  it('leaves an interpolated URL alone rather than linking the markup inside it', () => {
    const inputValue =
      '<span class="hljs-string">&quot;https://github.com/<span class="hljs-subst">#{org}</span>/repo.git&quot;</span>';

    expect(podspecLinker({ value: inputValue })).toBe(inputValue);
  });

  it('does not link other strings', () => {
    const inputValue =
      '<span class="">  s.name         </span><span class="">= </span><span class="hljs-string">&#39;Reachability&#39;</span>';

    expect(podspecLinker({ value: inputValue })).toBe(inputValue);
  });

  it('does not link a value that merely contains the word license', () => {
    // The word appears inside a string, not as the attribute, so Ruby does not link it
    // either: MethodLinker#method_call_regex anchors the name to the start of a line.
    const inputValue =
      '<span class="">  s.preserve_paths </span><span class="">= </span><span class="hljs-string">&#39;license.txt&#39;</span><span class="">, </span><span class="hljs-string">&#39;README.md&#39;</span>';

    expect(podspecLinker({ value: inputValue })).toBe(inputValue);
  });

  it('does not link a licence choosealicense.com has no page for', () => {
    const inputValue =
      '<span class="">  s.license </span><span class="">= </span><span class="">{ </span><span class="hljs-symbol">type:</span><span class=""> </span><span class="hljs-string">&#39;Commercial&#39;</span><span class=""> }</span>';

    expect(podspecLinker({ value: inputValue })).toBe(inputValue);
  });

  it('links a call with a space before the parenthesis', () => {
    const inputValue =
      '<span class="">  s.dependency </span><span class="">(</span><span class="hljs-string">&#39;SpaceParen&#39;</span><span class="">)</span>';
    const outputValue = `<span class="">  s.dependency </span><span class="">(</span><span class="hljs-string">&#39;${link(
      'SpaceParen',
      'https://cocoapods.org/pods/SpaceParen',
    )}&#39;</span><span class="">)</span>`;

    expect(podspecLinker({ value: inputValue })).toBe(outputValue);
  });

  // These two cases are highlighted the way the source viewer highlights them rather than
  // written out by hand, because wrapBidiChars runs before the linker there and its
  // warning markup is the thing under test.
  describe('with the source viewer plugin chain', () => {
    const highlight = (source) => hljs.highlight(source, { language: 'ruby' }).value;
    const linked = (source) => podspecLinker({ value: highlight(source) });
    // U+202E RIGHT-TO-LEFT OVERRIDE, one of the characters wrapBidiChars warns about.
    const BIDI_OVERRIDE = '‮';

    it('keeps the BiDi warning on a dependency name, leaving that pod unlinked', () => {
      const source = `s.dependency 'Evil${BIDI_OVERRIDE}Pod'`;
      const result = linked(source);

      expect(result).toBe(highlight(source));
      expect(result).toContain('class="unicode-bidi has-tooltip"');
      expect(result).not.toContain('cocoapods.org/pods/Evil');
    });

    it('escapes an ampersand in a dependency name exactly once', () => {
      const result = linked("s.dependency 'A&B'");

      expect(result).toContain(link('A&amp;B', 'https://cocoapods.org/pods/A&amp;B'));
      expect(result).not.toContain('&amp;amp;');
    });
  });
});
