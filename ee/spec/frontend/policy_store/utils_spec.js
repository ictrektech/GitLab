import * as Sentry from '~/sentry/sentry_browser_wrapper';
import {
  apiErrorMessage,
  EMPTY_CATALOGS,
  isDuplicateNameError,
  isPolicyWritable,
  isRuleRegoParseError,
  PolicyStoreMutationError,
  readMutationPayload,
  throwStoreErrors,
  toCatalogs,
} from 'ee/policy_store/utils';
import { NAMESPACE_TYPE_GROUP, NAMESPACE_TYPE_ORGANIZATION } from 'ee/policy_store/constants';
import { ACTIONS } from 'ee/policy_store/catalog/actions';
import { RULES } from 'ee/policy_store/catalog/rules';
import { TRIGGERS } from 'ee/policy_store/catalog/triggers';

jest.mock('~/sentry/sentry_browser_wrapper');

describe('apiErrorMessage', () => {
  it('returns the store message a rejected mutation carries', () => {
    const error = new PolicyStoreMutationError('Name has already been taken');

    expect(apiErrorMessage(error)).toBe('Name has already been taken');
  });

  it('returns an empty store message as-is for callers to fall back on', () => {
    expect(apiErrorMessage(new PolicyStoreMutationError(''))).toBe('');
  });

  it('returns the first top-level GraphQL error message the mutation raised', () => {
    const error = Object.assign(new Error('GraphQL error: not available'), {
      graphQLErrors: [{ message: 'not available' }, { message: 'second' }],
    });

    expect(apiErrorMessage(error)).toBe('not available');
  });

  // No policy store write goes over REST any more, so an axios-shaped
  // response body is not a store message and callers fall back to their copy.
  it.each`
    description                        | error
    ${'a request error'}               | ${new Error('network down')}
    ${'an empty GraphQL errors array'} | ${{ graphQLErrors: [] }}
    ${'an axios-shaped REST error'}    | ${{ response: { data: { message: 'Name has already been taken' } } }}
    ${'nothing at all'}                | ${undefined}
  `('returns nothing for $description', ({ error }) => {
    expect(apiErrorMessage(error)).toBeUndefined();
  });
});

describe('throwStoreErrors', () => {
  it('throws the store message as a PolicyStoreMutationError', () => {
    expect(() => throwStoreErrors(['Name has already been taken'])).toThrow(
      new PolicyStoreMutationError('Name has already been taken'),
    );
  });

  it('joins several messages so none is silently dropped', () => {
    expect(() => throwStoreErrors(['Policy is stale', 'Policy is locked'])).toThrow(
      'Policy is stale, Policy is locked',
    );
  });

  it.each`
    description         | errors
    ${'no errors'}      | ${[]}
    ${'a null payload'} | ${null}
    ${'no payload'}     | ${undefined}
  `('does nothing for $description', ({ errors }) => {
    expect(() => throwStoreErrors(errors)).not.toThrow();
  });
});

describe('readMutationPayload', () => {
  const payload = { __typename: 'GovernPolicyUpdatePayload', policy: { id: 7 }, errors: [] };

  it('returns the payload field of a successful mutation', () => {
    expect(readMutationPayload({ governPolicyUpdate: payload }, 'governPolicyUpdate')).toBe(
      payload,
    );
  });

  it('throws the store message when the payload carries errors', () => {
    const data = { governPolicyUpdate: { ...payload, errors: ['Policy is stale'] } };

    expect(() => readMutationPayload(data, 'governPolicyUpdate')).toThrow(
      new PolicyStoreMutationError('Policy is stale'),
    );
  });

  // Apollo rejects top-level errors itself, so a response with no payload and
  // no error is malformed: a plain Error, so callers fall back to generic copy.
  it.each`
    description          | data
    ${'a null payload'}  | ${{ governPolicyUpdate: null }}
    ${'a missing field'} | ${{}}
    ${'no data at all'}  | ${undefined}
  `('throws a plain error for $description', ({ data }) => {
    let thrown;

    try {
      readMutationPayload(data, 'governPolicyUpdate');
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toEqual(
      new Error('Policy store mutation returned no governPolicyUpdate payload'),
    );
    expect(thrown).not.toBeInstanceOf(PolicyStoreMutationError);
  });
});

describe('policy store catalogs', () => {
  const healthyPolicyStore = ({
    triggers = [{ id: 'deployment_requested', name: 'Deployment' }],
    rules = [{ id: 'custom', name: 'Custom' }],
    actions = [{ id: 'block', name: 'Block' }],
  } = {}) => ({ triggers, rules, actions });

  it('exposes empty catalogs for consumers to start from', () => {
    expect(EMPTY_CATALOGS).toEqual({ triggers: [], rules: [], actions: [] });
  });

  it('presents an id the local catalog knows with its full local entry', () => {
    const { catalogs, failedCatalogs } = toCatalogs(
      healthyPolicyStore({
        rules: [
          { id: 'calendar', name: 'Calendar' },
          { id: 'environment', name: 'Environment' },
        ],
      }),
    );

    expect(failedCatalogs).toEqual([]);
    expect(catalogs.triggers).toEqual([TRIGGERS.find(({ id }) => id === 'deployment_requested')]);
    expect(catalogs.rules).toEqual([
      RULES.find(({ id }) => id === 'calendar'),
      RULES.find(({ id }) => id === 'environment'),
    ]);
    expect(catalogs.actions).toEqual([ACTIONS.find(({ id }) => id === 'block')]);
  });

  it('presents an unknown id as a minimal entry named by the API', () => {
    const { catalogs } = toCatalogs(
      healthyPolicyStore({ rules: [{ id: 'holiday', name: 'Holiday' }] }),
    );

    expect(catalogs.rules).toEqual([
      { id: 'holiday', label: 'Holiday', description: '', icon: 'question-o', fields: [] },
    ]);
  });

  it('drops entries without an id, which cannot serve as the wire value', () => {
    const { catalogs } = toCatalogs(
      healthyPolicyStore({
        rules: [{}, { name: 'No id' }, { id: 'custom', name: 'Custom' }, null],
      }),
    );

    expect(catalogs.rules).toEqual([RULES.find(({ id }) => id === 'custom')]);
  });

  it('names an empty catalog as failed while the others keep their entries', () => {
    const { catalogs, failedCatalogs } = toCatalogs(healthyPolicyStore({ triggers: [] }));

    expect(failedCatalogs).toEqual(['triggers']);
    expect(catalogs.triggers).toEqual([]);
    expect(catalogs.rules).toEqual([RULES.find(({ id }) => id === 'custom')]);
    expect(catalogs.actions).toEqual([ACTIONS.find(({ id }) => id === 'block')]);
    expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error), {
      tags: { policyStoreCatalog: 'triggers' },
    });
  });

  it('names every failing catalog when several are empty', () => {
    const { failedCatalogs } = toCatalogs(healthyPolicyStore({ triggers: [], actions: [] }));

    expect(failedCatalogs).toEqual(['triggers', 'actions']);
  });

  it('treats a catalog with only unusable entries as failed', () => {
    const { failedCatalogs } = toCatalogs(healthyPolicyStore({ actions: [{}, { name: 'No id' }] }));

    expect(failedCatalogs).toEqual(['actions']);
  });

  it('treats a malformed catalog as failed', () => {
    const { failedCatalogs } = toCatalogs(healthyPolicyStore({ triggers: { not: 'an array' } }));

    expect(failedCatalogs).toEqual(['triggers']);
    expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(Error), {
      tags: { policyStoreCatalog: 'triggers' },
    });
  });

  it('fails every catalog for a null policyStore, as when the experiment is off', () => {
    const { catalogs, failedCatalogs } = toCatalogs(null);

    expect(failedCatalogs).toEqual(['triggers', 'rules', 'actions']);
    expect(catalogs).toEqual(EMPTY_CATALOGS);
  });
});

describe('isDuplicateNameError', () => {
  it.each`
    description                                          | message                                                                    | expected
    ${'the bare message both backends raise'}            | ${'Name has already been taken'}                                           | ${true}
    ${'the bare message regardless of case and padding'} | ${' name HAS already been taken '}                                         | ${true}
    ${'a sentence combining it with other failures'}     | ${'Name has already been taken and Namespace must match the organization'} | ${false}
    ${'an unrelated validation message'}                 | ${'rule 0: unsupported rule type "calendar"'}                              | ${false}
    ${'no message at all'}                               | ${undefined}                                                               | ${false}
  `('recognises $description as $expected', ({ message, expected }) => {
    expect(isDuplicateNameError(message)).toBe(expected);
  });
});

describe('isRuleRegoParseError', () => {
  it.each`
    description                                          | message                                                             | expected
    ${'the refusal the store raises for one error'}      | ${'rules[0] is invalid: expecting expression (at 5:1)'}             | ${true}
    ${"one rule's engine errors joined with '; '"}       | ${'rules[0] is invalid: unexpected token; missing value'}           | ${true}
    ${'an engine message that quotes source with ;'}     | ${'rules[0] is invalid: unexpected eof: allow { a; b } (at 1:1)'}   | ${true}
    ${'a truncated engine message'}                      | ${'rules[0] is invalid: expecting expression in rule body allo...'} | ${true}
    ${'a refusal for a rule past the first ten'}         | ${'rules[11] is invalid: expecting expression (at 1:1)'}            | ${true}
    ${'a refusal with surrounding padding'}              | ${'  rules[0] is invalid: expecting expression (at 5:1)  '}         | ${true}
    ${'a merged-module engine fault, a different shape'} | ${'policy_merged_program is invalid: var msg is unsafe (at 3:3)'}   | ${false}
    ${'a scope refusal, a different field'}              | ${'scope_rego is invalid: expecting expression (at 1:1)'}           | ${false}
    ${'an engine fault, which is not a parse failure'}   | ${'rules[0] could not be validated'}                                | ${false}
    ${'an unrelated validation message'}                 | ${'Name has already been taken'}                                    | ${false}
    ${'a non-Rego rule validation message'}              | ${'rule 0: unsupported rule type "calendar"'}                       | ${false}
    ${'an empty message'}                                | ${''}                                                               | ${false}
    ${'no message at all'}                               | ${undefined}                                                        | ${false}
  `('recognises $description as $expected', ({ message, expected }) => {
    expect(isRuleRegoParseError(message)).toBe(expected);
  });
});

describe('isPolicyWritable', () => {
  const group = (fullPath) => ({ group: { fullPath } });

  it.each`
    description                                     | policy                   | container                                                                 | expected
    ${'an organization writes any policy it lists'} | ${group('flightjs')}     | ${{ namespaceType: NAMESPACE_TYPE_ORGANIZATION, namespacePath: '' }}      | ${true}
    ${'an organization writes its own policy'}      | ${{ group: null }}       | ${{ namespaceType: NAMESPACE_TYPE_ORGANIZATION, namespacePath: '' }}      | ${true}
    ${'a group writes the policy it owns'}          | ${group('flightjs')}     | ${{ namespaceType: NAMESPACE_TYPE_GROUP, namespacePath: 'flightjs' }}     | ${true}
    ${'a group cannot write an inherited policy'}   | ${{ group: null }}       | ${{ namespaceType: NAMESPACE_TYPE_GROUP, namespacePath: 'flightjs' }}     | ${false}
    ${'a group cannot write an ancestor policy'}    | ${group('flightjs')}     | ${{ namespaceType: NAMESPACE_TYPE_GROUP, namespacePath: 'flightjs/sub' }} | ${false}
    ${'a group cannot write a descendant policy'}   | ${group('flightjs/sub')} | ${{ namespaceType: NAMESPACE_TYPE_GROUP, namespacePath: 'flightjs' }}     | ${false}
    ${'a missing policy is not writable'}           | ${null}                  | ${{ namespaceType: NAMESPACE_TYPE_GROUP, namespacePath: 'flightjs' }}     | ${false}
  `('$description', ({ policy, container, expected }) => {
    expect(isPolicyWritable(policy, container)).toBe(expected);
  });
});
