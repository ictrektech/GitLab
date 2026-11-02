/* global __webpack_require__ */
/* eslint-disable camelcase */

const runtime = __webpack_require__;
const applyCssUpdate = runtime.hmrC?.css;

const baseUrl = (href) => href.split('?')[0];
const chunkUrl = (chunkId) => {
  const filename = runtime.k(chunkId);
  return filename && new URL(runtime.p + filename, document.baseURI).href;
};
const stylesheetLinks = () => Array.from(document.querySelectorAll('link[rel="stylesheet"]'));

if (applyCssUpdate) {
  runtime.hmrC.css = (...args) => {
    const css = args[6];
    const mediaByUrl = new Map(stylesheetLinks().map((link) => [baseUrl(link.href), link.media]));

    // Every stylesheet entry is an initial chunk of the shared runtime, so Rspack would inject
    // the stylesheets of all entries sharing an edited partial, even ones this page never linked.
    const onPageCss = css?.c
      ? { ...css, c: css.c.filter((chunkId) => mediaByUrl.has(chunkUrl(chunkId))) }
      : css;

    applyCssUpdate(...args.slice(0, 6), onPageCss);

    // Rspack builds the replacement <link> from scratch, dropping the color-scheme media query.
    stylesheetLinks().forEach((link) => {
      const media = mediaByUrl.get(baseUrl(link.href));
      if (media && !link.media) link.setAttribute('media', media);
    });
  };
}
