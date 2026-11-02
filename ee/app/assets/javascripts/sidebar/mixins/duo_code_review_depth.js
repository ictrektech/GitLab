import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';

export default {
  mixins: [glFeatureFlagsMixin()],
  computed: {
    duoCodeReviewDepthChoiceEnabled() {
      return Boolean(this.glFeatures.duoCodeReviewDeepFlow);
    },
  },
};
