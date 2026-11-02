import { OPERATORS_OR } from '~/vue_shared/components/filtered_search_bar/constants';
import TrackedRefToken from 'ee/security_dashboard/components/shared/filtered_search/tokens/tracked_ref_token.vue';

// The token pre-applies the default branch, so `trackedRefIds` reaches the dependency query on
// load, where only Elasticsearch can answer it. Without the ability the backend rejects it and
// the list fails to render, so don't offer the token at all.
export const isTrackedRefFilterEnabled = ({
  glFeatures = {},
  glAbilities = {},
  projectFullPath = '',
  defaultBranchContext = null,
} = {}) =>
  Boolean(
    glFeatures.vulnerabilitiesAcrossContexts &&
    glFeatures.projectDependencyTrackedRef &&
    glAbilities.readAdvancedDependencyManagement &&
    projectFullPath &&
    defaultBranchContext,
  );

export const buildDefaultTrackedRefFilter = (defaultBranchContext) => {
  const data = TrackedRefToken.defaultValues({ defaultBranchContext });

  if (!data.length) {
    return [];
  }

  return [
    {
      type: 'trackedRefIds',
      value: { data, operator: OPERATORS_OR[0].value },
    },
  ];
};
