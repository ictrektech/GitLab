import {
  DUO_CODE_REVIEW_DEPTHS,
  DUO_CODE_REVIEW_DEPTHS_HEADER_KEY,
  RELEASE_STATE_DISPLAY_ORDER,
} from './constants';

const compareTitles = (a, b) => (a.title || '').localeCompare(b.title || '');

const releaseStateRank = ({ releaseState }) =>
  RELEASE_STATE_DISPLAY_ORDER[releaseState] ?? Number.MAX_SAFE_INTEGER;

export const sortFeatureSettingsByTitle = (featureSettings) =>
  [...featureSettings].sort(compareTitles);

export const sortFeatureSettingsByReleaseStateThenTitle = (featureSettings) =>
  [...featureSettings].sort(
    (a, b) => releaseStateRank(a) - releaseStateRank(b) || compareTitles(a, b),
  );

// When both Code Review depths are listed, show them as one block where the first of them
// sorted to: a header row with the feature title, then one indented row per depth.
export const groupDuoCodeReviewDepths = (featureSettings) => {
  const depthSettings = Object.keys(DUO_CODE_REVIEW_DEPTHS)
    .map((feature) => featureSettings.find((setting) => setting.feature === feature))
    .filter(Boolean);

  if (depthSettings.length < 2) return featureSettings;

  const header = {
    feature: DUO_CODE_REVIEW_DEPTHS_HEADER_KEY,
    title: depthSettings[0].title,
    isDepthHeader: true,
  };
  const depthRows = depthSettings.map((setting, index) => ({
    ...setting,
    depthLabel: DUO_CODE_REVIEW_DEPTHS[setting.feature].label,
    depthDescription: DUO_CODE_REVIEW_DEPTHS[setting.feature].description,
    isDepthChild: true,
    isDepthBlockEnd: index === depthSettings.length - 1,
  }));

  let blockAdded = false;

  return featureSettings.flatMap((setting) => {
    if (!DUO_CODE_REVIEW_DEPTHS[setting.feature]) return [setting];
    if (blockAdded) return [];

    blockAdded = true;
    return [header, ...depthRows];
  });
};
