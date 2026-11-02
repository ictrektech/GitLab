import excludedGroupCreateMutation from '../../graphql/mutations/excluded_group_create.mutation.graphql';
import excludedGroupDestroyMutation from '../../graphql/mutations/excluded_group_destroy.mutation.graphql';
import orbitStartTrialMutation from '../../graphql/mutations/orbit_start_trial.mutation.graphql';
import orbitUpdateMutation from '../../graphql/mutations/orbit_update.mutation.graphql';
import {
  ACTION_ERROR_KIND,
  ACTION_EXCLUDE,
  ACTION_INCLUDE,
  ACTION_TURN_OFF,
  ACTION_TURN_ON,
} from './constants';
import { requestErrorFor } from './utils';

const START_TRIAL = {
  mutation: orbitStartTrialMutation,
  payload: 'orbitStartTrial',
  variables: (group) => ({ groupPath: group.fullPath }),
};

const ACTION_MUTATIONS = {
  [ACTION_TURN_ON]: {
    mutation: orbitUpdateMutation,
    payload: 'orbitUpdate',
    variables: (group) => ({ input: { groupPath: group.fullPath, enabled: true } }),
  },
  [ACTION_TURN_OFF]: {
    mutation: orbitUpdateMutation,
    payload: 'orbitUpdate',
    variables: (group) => ({ input: { groupPath: group.fullPath, enabled: false } }),
  },
  [ACTION_EXCLUDE]: {
    mutation: excludedGroupCreateMutation,
    payload: 'orbitExcludedGroupCreate',
    variables: (group) => ({ groupPath: group.fullPath }),
  },
  [ACTION_INCLUDE]: {
    mutation: excludedGroupDestroyMutation,
    payload: 'orbitExcludedGroupDestroy',
    variables: (group) => ({ groupPath: group.fullPath }),
  },
};

// orbitStartTrial also turns Orbit on.
export async function mutateGroup(apollo, { action, group, noAccessMessage }) {
  const { mutation, payload, variables } =
    action === ACTION_TURN_ON && group.startsTrial ? START_TRIAL : ACTION_MUTATIONS[action];

  try {
    const { data } = await apollo.mutate({ mutation, variables: variables(group) });
    // A backend older than the mutation returns a null payload (@gl_introduced).
    if (!data?.[payload]) {
      return { failure: requestErrorFor({}), error: new Error(`${payload} returned no payload`) };
    }

    const { errors } = data[payload];
    const failure = errors.length
      ? { kind: ACTION_ERROR_KIND.REJECTED, message: errors.join(' ') }
      : null;
    return { failure };
  } catch (error) {
    return { failure: requestErrorFor(error, { noAccessMessage }), error };
  }
}
