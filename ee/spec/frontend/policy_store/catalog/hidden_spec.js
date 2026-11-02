import { ACTIONS } from 'ee/policy_store/catalog/actions';
import { HIDDEN_CATALOG_IDS } from 'ee/policy_store/catalog/hidden';
import { RULES } from 'ee/policy_store/catalog/rules';
import { TRIGGERS } from 'ee/policy_store/catalog/triggers';

const CATALOGS = { triggers: TRIGGERS, rules: RULES, actions: ACTIONS };

describe('HIDDEN_CATALOG_IDS', () => {
  it('names a picker for every catalog, so adding an id is editing a line', () => {
    expect(Object.keys(HIDDEN_CATALOG_IDS).sort()).toEqual(Object.keys(CATALOGS).sort());
  });

  // Hiding is by id, so an id that names nothing hides nothing: either it is a typo, or the
  // entry was renamed and is being offered again under its new id.
  it.each(Object.keys(CATALOGS))('hides only ids the %s catalog still has', (name) => {
    const known = CATALOGS[name].map(({ id }) => id);

    expect(known).toEqual(expect.arrayContaining(HIDDEN_CATALOG_IDS[name]));
  });
});
