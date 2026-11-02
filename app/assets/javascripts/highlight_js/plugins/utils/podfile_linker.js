import { unescape } from 'lodash-es';
import { createLink, generateHLJSOpenTag } from './dependency_linker_util';

const POD_URL = 'https://cocoapods.org/pods/';
const POD_STRING = 'pod </span>';
const DELIMITERS = ['&#39;', '&quot;'];

/*
 * Detects a pod declaration and the remainder of its line inside content that is
 * highlighted by Highlight.js.
 * The name stops at `<`, so a name carrying markup of its own, as one holding a BiDi
 * control character does, fails the delimiter lookahead and keeps its warning span.
 * Example: 'pod </span><span class="hljs-string">&#39;AFNetworking&#39;</span>, ...'
 * Group 1 (podName): 'AFNetworking'
 * Group 2 (rest): the rest of the line, re-emitted untouched
 */
const POD_REGEXES = DELIMITERS.map((delimiter) => [
  delimiter,
  new RegExp(
    `${POD_STRING}${generateHLJSOpenTag('string', delimiter)}([^<\n]+?(?=${delimiter}))(${delimiter}[^\n]*)`,
    'gm',
  ),
]);

/*
 * Detects a string that is itself a URL, such as a `source` or a `:git` ref.
 * The match stops at whitespace and at `<`, so an interpolated URL, which carries raw
 * markup for the interpolated part, is left alone rather than linked with that markup.
 * Example: '<span class="hljs-string">&#39;https://cdn.cocoapods.org/&#39;'
 * Group 1 (url): 'https://cdn.cocoapods.org/'
 */
const URL_REGEXES = DELIMITERS.map((delimiter) => [
  delimiter,
  new RegExp(
    `${generateHLJSOpenTag('string', delimiter)}(https?://[^\\s<]+?(?=${delimiter}))`,
    'gm',
  ),
]);

// Mirrors Gitlab::DependencyLinker::GemfileLinker::GIT_REGEX. It runs against the line's
// plain text because Highlight.js splits `:git` across several spans, so the marked-up
// line never holds it as one token.
const GIT_SOURCE_REGEX = /(?:git:|:git\s*=>)\s*['"](https?:\/\/[^'" ]+)['"]/;

const plainText = (markup) => unescape(markup.replace(/<[^>]*>/g, ''));

const podHref = (podName, rest) => {
  // A pod pinned to a git source lives there rather than in the registry.
  const gitSource = plainText(rest).match(GIT_SOURCE_REGEX);
  // An interpolated URL only resolves at runtime, and the capture stops at the opening
  // quote of the interpolation, so there is no honest destination for this pod.
  if (gitSource) return gitSource[1].includes('#{') ? null : gitSource[1];

  // A subspec such as `SDWebImage/WebP` lives under its parent pod's page.
  return `${POD_URL}${podName.split('/')[0]}`;
};

// eslint-disable-next-line max-params
const linkPod = (original, delimiter, podName, rest) => {
  // The name arrives HTML-escaped and createLink escapes what it is given, so an
  // ampersand in a pod name would otherwise come back doubly escaped.
  const name = unescape(podName);
  const href = podHref(name, rest);

  if (!href) return original;

  return `${POD_STRING}${generateHLJSOpenTag('string', delimiter)}${createLink(href, name)}${rest}`;
};

const linkUrl = (delimiter, url) => {
  // The value arrives HTML-escaped, and createLink escapes what it is given, so an
  // ampersand in a query string would otherwise come back doubly escaped.
  const unescapedUrl = unescape(url);

  return `${generateHLJSOpenTag('string', delimiter)}${createLink(unescapedUrl, unescapedUrl)}`;
};

export default (result) => {
  const withPods = POD_REGEXES.reduce(
    (value, [delimiter, regex]) =>
      value.replace(regex, (original, podName, rest) =>
        linkPod(original, delimiter, podName, rest),
      ),
    result.value,
  );

  return URL_REGEXES.reduce(
    (value, [delimiter, regex]) => value.replace(regex, (_, url) => linkUrl(delimiter, url)),
    withPods,
  );
};
