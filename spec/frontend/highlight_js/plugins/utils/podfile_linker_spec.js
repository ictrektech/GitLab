import hljs from 'highlight.js/lib/core';
import ruby from 'highlight.js/lib/languages/ruby';
import wrapChildNodes from '~/highlight_js/plugins/wrap_child_nodes';
import wrapBidiChars from '~/highlight_js/plugins/wrap_bidi_chars';
import podfileLinker from '~/highlight_js/plugins/utils/podfile_linker';

// The input is produced the way the source viewer produces it, rather than written out by
// hand: Highlight.js splits tokens such as `:git` across several spans, and hand-written
// markup hid that from these examples. wrapBidiChars runs before the linker there too, so
// it is registered here in the same order.
hljs.registerLanguage('ruby', ruby);
hljs.addPlugin({ 'after:highlight': wrapChildNodes });
hljs.addPlugin({ 'after:highlight': wrapBidiChars });

const highlight = (source) => hljs.highlight(source, { language: 'ruby' }).value;
const linked = (source) => podfileLinker({ value: highlight(source) });

describe('Highlight.js plugin for linking Podfile dependencies', () => {
  const anchor = (href, text) =>
    `<a href="${href}" target="_blank" rel="nofollow noreferrer noopener">${text}</a>`;
  const podLink = (name, slug = name) => anchor(`https://cocoapods.org/pods/${slug}`, name);
  // U+202E RIGHT-TO-LEFT OVERRIDE, one of the characters wrapBidiChars warns about.
  const BIDI_OVERRIDE = '\u202E';

  it('links a pod name to its page, in either quote style', () => {
    const result = linked("pod 'AFNetworking', '~> 3.0'\npod \"Mantle\"");

    expect(result).toContain(podLink('AFNetworking'));
    expect(result).toContain(podLink('Mantle'));
  });

  it('links a subspec to its parent pod, in either quote style', () => {
    const result = linked('pod \'SDWebImage/WebP\'\npod "AFNetworking/Security"');

    expect(result).toContain(podLink('SDWebImage/WebP', 'SDWebImage'));
    expect(result).toContain(podLink('AFNetworking/Security', 'AFNetworking'));
  });

  it('links a source URL to itself', () => {
    const url = 'https://cdn.cocoapods.org/';

    expect(linked(`source '${url}'`)).toContain(anchor(url, url));
  });

  it('points a pod pinned with :git at that source, and links the URL too', () => {
    const url = 'https://github.com/gitterHQ/SlackTextViewController';
    const result = linked(`pod 'SlackTextViewController', :git => '${url}'`);

    expect(result).toContain(anchor(url, 'SlackTextViewController'));
    expect(result).toContain(anchor(url, url));
    expect(result).not.toContain('cocoapods.org/pods/SlackTextViewController');
  });

  it('points a pod pinned with the git: shorthand at that source', () => {
    const url = 'https://github.com/atomicobject/objection.git';
    const result = linked(`pod 'Objection', git: '${url}'`);

    expect(result).toContain(anchor(url, 'Objection'));
    expect(result).not.toContain('cocoapods.org/pods/Objection');
  });

  it('does not use a git source that belongs to a different pod line', () => {
    const url = 'https://github.com/gitterHQ/SlackTextViewController';
    const result = linked(`pod 'AFNetworking'\npod 'Slack', :git => '${url}'`);

    expect(result).toContain(podLink('AFNetworking'));
  });

  it('keeps an escaped query string inside a URL', () => {
    const url = 'https://example.com/specs.git?a=1&b=2';
    const result = linked(`source '${url}'`);

    expect(result).toContain(`href="https://example.com/specs.git?a=1&amp;b=2"`);
    expect(result).not.toContain('&amp;amp;');
  });

  it('leaves an interpolated URL alone rather than linking the markup inside it', () => {
    const source = 'source "https://#{host}/specs.git"';

    expect(linked(source)).toBe(highlight(source));
  });

  it('keeps the BiDi warning on a pod name, leaving that pod unlinked', () => {
    const source = `pod 'Evil${BIDI_OVERRIDE}Pod'`;
    const result = linked(source);

    expect(result).toBe(highlight(source));
    expect(result).toContain('class="unicode-bidi has-tooltip"');
    expect(result).not.toContain('cocoapods.org/pods/Evil');
  });

  it('escapes an ampersand in a pod name exactly once', () => {
    const result = linked("pod 'A&B'");

    expect(result).toContain(anchor('https://cocoapods.org/pods/A&amp;B', 'A&amp;B'));
    expect(result).not.toContain('&amp;amp;');
  });

  it('leaves a pod unlinked when its git source is interpolated', () => {
    const source = `pod 'Interp', :git => "https://#{ENV['HOST']}/interp.git"`;
    const result = linked(source);

    expect(result).toBe(highlight(source));
    expect(result).not.toContain('cocoapods.org/pods/Interp');
  });

  it('does not link strings that are neither pod names nor URLs', () => {
    const source = "target 'MyApp'\nplatform :ios, '12.0'";

    expect(linked(source)).toBe(highlight(source));
  });
});
