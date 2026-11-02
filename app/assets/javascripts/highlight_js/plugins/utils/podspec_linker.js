import { unescape } from 'lodash-es';
import { createLink, generateHLJSOpenTag } from './dependency_linker_util';

const POD_URL = 'https://cocoapods.org/pods/';
const LICENSE_URL = 'https://choosealicense.com/licenses/';
// The identifiers choosealicense.com actually hosts a page for. Ruby resolves the value
// through Licensee::License.find and leaves anything it does not know as plain text, so
// linking every identifier-shaped value would point `{ type: 'Commercial' }` at a 404.
const CHOOSEALICENSE_IDS = new Set([
  '0bsd',
  'afl-3.0',
  'agpl-3.0',
  'apache-2.0',
  'artistic-2.0',
  'blueoak-1.0.0',
  'bsd-2-clause',
  'bsd-2-clause-patent',
  'bsd-3-clause',
  'bsd-3-clause-clear',
  'bsd-4-clause',
  'bsl-1.0',
  'cc-by-4.0',
  'cc-by-sa-4.0',
  'cc0-1.0',
  'cecill-2.1',
  'cern-ohl-p-2.0',
  'cern-ohl-s-2.0',
  'cern-ohl-w-2.0',
  'ecl-2.0',
  'epl-1.0',
  'epl-2.0',
  'eupl-1.1',
  'eupl-1.2',
  'gfdl-1.3',
  'gpl-2.0',
  'gpl-3.0',
  'isc',
  'lgpl-2.1',
  'lgpl-3.0',
  'lppl-1.3c',
  'mit',
  'mit-0',
  'mpl-2.0',
  'ms-pl',
  'ms-rl',
  'mulanpsl-2.0',
  'ncsa',
  'odbl-1.0',
  'ofl-1.1',
  'osl-3.0',
  'postgresql',
  'unlicense',
  'upl-1.0',
  'vim',
  'wtfpl',
  'zlib',
]);
// The Ruby linker allows any whitespace or a parenthesis after the method name, and
// Highlight.js closes and reopens a span around the parenthesis. A call written
// `s.dependency ('X')` puts the space and the parenthesis in different spans, so the run
// has to allow the markup and the characters in any order rather than one after the
// other. It is bounded, and none of the pieces it allows can cross a quoted value, so it
// cannot reach a string further along the line.
const DEPENDENCY_PREFIX = 'dependency(?:[ \\t(]|</span>|<span class="">){0,50}';
// Mirrors the look-behind in MethodLinker#method_call_regex: the start of a line, the
// indentation, and an optional receiver such as `s.`. Anchoring here is what stops the
// word `license` inside a value from matching, as in
// `s.preserve_paths = 'license.txt', 'README.md'`, and it leaves the engine a line start
// to try rather than every occurrence of the word on a long line.
const ATTRIBUTE_PREFIX = '(?:^|\\n)(?:</?span[^>]*>|\\s){0,30}(?:[\\w.]{1,100}\\.)?';
// Everything between the keyword and the quoted value, which rules out a string span so
// the match cannot reach across to an unrelated value on the same line. Bounded, because
// an unbounded lazy run carrying a look-ahead per character is slow on a long line.
const UNTIL_VALUE = '(?:(?!hljs-string)[^\\n]){0,400}?';
const DELIMITERS = ['&#39;', '&quot;'];

const dependencyRegex = (delimiter) =>
  new RegExp(
    /*
     * Detects dependencies inside of content that is highlighted by Highlight.js
     * The name stops at `<`, so a name carrying markup of its own, as one holding a BiDi
     * control character does, fails the delimiter lookahead and keeps its warning span.
     * Example: 's.dependency </span><span class="hljs-string">&#39;AFNetworking&#39;'
     * Group 1 (prefix): 'dependency </span>'
     * Group 2 (podName): 'AFNetworking'
     */
    `(${DEPENDENCY_PREFIX})${generateHLJSOpenTag('string', delimiter)}([^<\\n]+?(?=${delimiter}))`,
    'gm',
  );

const licenseRegex = (delimiter) =>
  new RegExp(
    /*
     * Detects the license, both as a plain value and as the type key of a hash
     * Example: 's.license      </span><span class="">= </span><span class="hljs-string">&#39;MIT&#39;'
     * Group 1 (prefix): the line start, the receiver, the keyword, and everything from
     *   the keyword up to the quoted value
     * Group 2 (license): 'MIT'
     */
    `(${ATTRIBUTE_PREFIX}license${UNTIL_VALUE})${generateHLJSOpenTag('string', delimiter)}([\\w.+-]+?(?=${delimiter}))`,
    'gm',
  );

const urlRegex = (delimiter) =>
  new RegExp(
    /*
     * Detects URL strings such as the homepage or the git source. The match stops at
     * whitespace and at `<`, so an interpolated URL, which carries raw markup for the
     * interpolated part, is left alone rather than linked with that markup inside it.
     * Example: '<span class="hljs-string">&#39;https://github.com/tonymillion/Reachability&#39;'
     * Group 1 (url): 'https://github.com/tonymillion/Reachability'
     */
    `${generateHLJSOpenTag('string', delimiter)}(https?://[^\\s<]+?(?=${delimiter}))`,
    'gm',
  );

const linkDependency = (prefix, delimiter, podName) => {
  // The name arrives HTML-escaped and createLink escapes what it is given, so an
  // ampersand in a pod name would otherwise come back doubly escaped.
  const name = unescape(podName);
  // A subspec such as `SDWebImage/WebP` lives under its parent pod's page.
  const podLink = createLink(`${POD_URL}${name.split('/')[0]}`, name);
  return `${prefix}${generateHLJSOpenTag('string', delimiter)}${podLink}`;
};

// An identifier choosealicense.com does not host stays plain text, as it does in Ruby.
const isLinkableLicense = (license) => CHOOSEALICENSE_IDS.has(license.toLowerCase());

const linkLicense = (prefix, delimiter, license) => {
  const licenseLink = createLink(`${LICENSE_URL}${license.toLowerCase()}/`, license);
  return `${prefix}${generateHLJSOpenTag('string', delimiter)}${licenseLink}`;
};

const linkUrl = (delimiter, url) => {
  // The value arrives HTML-escaped, and createLink escapes what it is given, so an
  // ampersand in a query string would otherwise come back doubly escaped.
  const unescapedUrl = unescape(url);

  return `${generateHLJSOpenTag('string', delimiter)}${createLink(unescapedUrl, unescapedUrl)}`;
};

export default (result) => {
  return DELIMITERS.reduce(
    (value, delimiter) =>
      value
        .replace(dependencyRegex(delimiter), (_, prefix, podName) =>
          linkDependency(prefix, delimiter, podName),
        )
        .replace(licenseRegex(delimiter), (match, prefix, license) =>
          isLinkableLicense(license) ? linkLicense(prefix, delimiter, license) : match,
        )
        .replace(urlRegex(delimiter), (_, url) => linkUrl(delimiter, url)),
    result.value,
  );
};
