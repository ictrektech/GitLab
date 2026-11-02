import fs from 'fs';
import path from 'path';
import { ACTIONS } from 'ee/policy_store/catalog/actions';
import { RULES } from 'ee/policy_store/catalog/rules';
import { RECORDED_TRIGGERS, TRIGGERS } from 'ee/policy_store/catalog/triggers';

// The wire ids in the frontend catalog and in Gitlab::PolicyStore are one vocabulary split
// across two languages, and the write endpoints constrain saves against the gem's half. Each
// half is pinned to literals by its own specs, so renaming one alone keeps every spec green
// while the entry silently stops being offerable (or savable). This spec is the only thing
// that reads both.
const GEM_DIR = path.join(
  __dirname,
  '../../../../../gems/gitlab-policy-store/lib/gitlab/policy_store',
);

// Entries the frontend offers before the gem can store them. Each needs the issue that lands
// it, and the final assertion deletes the need for the entry the moment that issue merges.
const AHEAD_OF_GEM = {
  actions: {},
  rules: {},
  triggers: {},
};

const gemSource = (basename) => {
  const file = path.join(GEM_DIR, `${basename}.rb`);

  try {
    return fs.readFileSync(file, 'utf8');
  } catch (error) {
    throw new Error(`Could not read ${file} — has the gem catalog moved?`, { cause: error });
  }
};

// The string constants a gem catalog file declares above its lists.
const gemConstants = (source) =>
  Object.fromEntries(
    [...source.matchAll(/^\s*([A-Z][A-Z_]*) = '([^']+)'/gm)].map(([, name, value]) => [
      name,
      value,
    ]),
  );

const gemList = (source, basename, constant) => {
  const list = source.match(new RegExp(`\\b${constant} = \\[(.*?)\\]\\.freeze`, 's'));

  if (!list) {
    throw new Error(`Could not find ${constant} in ${basename}.rb — has the gem catalog moved?`);
  }

  return list[1];
};

// Pulls the ids out of a `ALL = [...].freeze` literal, resolving the string constants the
// file declares above it (actions.rb names its ids; rules.rb and triggers.rb inline them).
const gemIds = (basename) => {
  const source = gemSource(basename);
  const constants = gemConstants(source);

  return [
    ...gemList(source, basename, 'ALL').matchAll(/\{\s*id:\s*(?:'([^']+)'|([A-Z][A-Z_]*))/g),
  ].map(([, literal, constant]) => literal ?? constants[constant]);
};

// `TYPES` is the gem's persisted vocabulary — a bare list of the constants above it,
// rather than ALL's hashes. Everything it holds beyond ALL is recorded by the engine and
// is never authored.
const gemStorableIds = (basename) => {
  const source = gemSource(basename);
  const constants = gemConstants(source);

  return [...gemList(source, basename, 'TYPES').matchAll(/[A-Z][A-Z_]*/g)].map(
    ([constant]) => constants[constant],
  );
};

describe('policy store catalog parity with the gitlab-policy-store gem', () => {
  describe.each`
    name          | basename      | entries
    ${'actions'}  | ${'actions'}  | ${ACTIONS}
    ${'rules'}    | ${'rules'}    | ${RULES}
    ${'triggers'} | ${'triggers'} | ${TRIGGERS}
  `('$name', ({ name, basename, entries }) => {
    const frontendIds = entries.map(({ id }) => id);
    const backendIds = gemIds(basename);
    const ahead = AHEAD_OF_GEM[name];

    it('parses a non-empty catalog out of the gem', () => {
      expect(backendIds.length).toBeGreaterThan(0);
      expect(backendIds).toEqual(backendIds.filter(Boolean));
    });

    it('offers every id the gem holds', () => {
      expect(frontendIds).toEqual(expect.arrayContaining(backendIds));
    });

    it('offers no id the gem cannot store, beyond the documented ones', () => {
      expect(frontendIds.filter((id) => !backendIds.includes(id) && !ahead[id])).toEqual([]);
    });

    // Keeps AHEAD_OF_GEM from outliving its reason: once the issue lands the id in the gem,
    // this fails until the entry is deleted.
    it('lists nothing in AHEAD_OF_GEM that the gem now holds', () => {
      expect(Object.keys(ahead).filter((id) => backendIds.includes(id))).toEqual([]);
    });
  });

  // A recorded trigger is not a trigger the frontend is ahead of: it is one the gem stores
  // and deliberately refuses to author, so it belongs in neither TRIGGERS nor AHEAD_OF_GEM.
  // These assertions pin the frontend's split to the gem's TYPES / ALL split.
  describe('recorded triggers', () => {
    const recordedIds = RECORDED_TRIGGERS.map(({ id }) => id);
    const authorableIds = gemIds('triggers');
    const storableIds = gemStorableIds('triggers');

    it('parses a persisted vocabulary out of the gem that is wider than the catalogue', () => {
      expect(storableIds).toEqual(expect.arrayContaining(authorableIds));
      expect(storableIds.length).toBeGreaterThan(authorableIds.length);
    });

    it('presents only ids the gem can store', () => {
      expect(storableIds).toEqual(expect.arrayContaining(recordedIds));
    });

    it('presents nothing the gem lets an author pick', () => {
      expect(recordedIds.filter((id) => authorableIds.includes(id))).toEqual([]);
    });

    // Without this an id the gem starts recording would reach a surface as its raw wire
    // value, which is the leak the split exists to close.
    it('presents every id the gem records but refuses to author', () => {
      const unpresented = storableIds.filter(
        (id) => !authorableIds.includes(id) && !recordedIds.includes(id),
      );

      expect(unpresented).toEqual([]);
    });
  });
});
