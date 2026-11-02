import { escape, quote } from './link';

function getMediaSrc(node, useCanonicalSrc = true) {
  const { canonicalSrc, src } = node.attrs;

  if (useCanonicalSrc) return canonicalSrc || src || '';
  return src || '';
}

function image(state, node) {
  const { alt, title, width, height, float, controlsList, isReference } = node.attrs;

  const realSrc = escape(getMediaSrc(node, state.options.useCanonicalSrc));
  // eslint-disable-next-line @gitlab/require-i18n-strings
  if (realSrc.startsWith('data:') || realSrc.startsWith('blob:')) return;

  if (realSrc) {
    const quotedTitle = title ? ` ${quote(title)}` : '';
    const sourceExpression = isReference ? `[${realSrc}]` : `(${realSrc}${quotedTitle})`;

    const attributeList = [];
    if (width) {
      attributeList.push(`width=${JSON.stringify(width)}`);
    }
    if (height) {
      attributeList.push(`height=${JSON.stringify(height)}`);
    }
    if (float) {
      attributeList.push(`.float-${float}`);
    }
    if (controlsList === 'nodownload') {
      attributeList.push(`controlslist=${controlsList}`);
    }

    const attributes = attributeList.length ? `{${attributeList.join(' ')}}` : '';

    state.write(`![${escape(alt || '')}]${sourceExpression}${attributes}`);
  }
}

export default image;
