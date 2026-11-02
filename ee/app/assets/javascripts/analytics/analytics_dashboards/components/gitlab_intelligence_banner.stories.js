import '../../../../stylesheets/page_bundles/analytics_dashboards.scss';
import GitlabIntelligenceBanner from './gitlab_intelligence_banner.vue';

export default {
  component: GitlabIntelligenceBanner,
  title: 'ee/analytics/analytics_dashboards/components/gitlab_intelligence_banner',
};

const Template = (args) => ({
  components: { GitlabIntelligenceBanner },
  provide: {},
  data() {
    return { ...args };
  },
  template: `<gitlab-intelligence-banner :explore-dashboards-path="exploreDashboardsPath" />`,
});

export const Default = {
  render: Template,
  args: {
    exploreDashboardsPath: '/explore/analytics_dashboards',
  },
};
