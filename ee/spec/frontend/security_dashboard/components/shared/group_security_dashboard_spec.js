import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlDashboardLayout } from '@gitlab/ui';
import { createAlert } from '~/alert';
import * as urlUtils from '~/lib/utils/url_utility';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import {
  OPERATORS_OR,
  OPERATORS_OR_NOT,
} from '~/vue_shared/components/filtered_search_bar/constants';
import getSecurityCategoriesAndAttributes from 'ee/security_configuration/graphql/group_security_categories_and_attributes.query.graphql';
import AttributeToken from 'ee/security_configuration/security_attributes/components/shared/attribute_token.vue';
import {
  SEVERITY_LEVELS_KEYS,
  REPORT_TYPES_WITH_MANUALLY_ADDED,
  REPORT_TYPES_CONTAINER_SCANNING_FOR_REGISTRY,
  REPORT_TYPES_WITH_CLUSTER_IMAGE,
} from 'ee/security_dashboard/constants';
import FilteredSearch from 'ee/security_dashboard/components/shared/filtered_search/filtered_search.vue';
import GroupSecurityDashboard from 'ee/security_dashboard/components/shared/group_security_dashboard.vue';
import ProjectToken from 'ee/security_dashboard/components/shared/filtered_search/tokens/project_token.vue';
import ReportTypeToken from 'ee/security_dashboard/components/shared/filtered_search/tokens/report_type_token.vue';
import VulnerabilitiesOverTimePanel from 'ee/security_dashboard/components/shared/vulnerabilities_over_time_panel.vue';
import VulnerabilitiesByAgePanel from 'ee/security_dashboard/components/shared/vulnerabilities_by_age_panel.vue';
import VulnerabilitiesByIdentifierPanel from 'ee/security_dashboard/components/shared/vulnerabilities_by_identifier_panel.vue';
import AgenticAdoptionFunnelPanel from 'ee/security_dashboard/components/shared/agentic_adoption_funnel_panel.vue';
import MttrOverTimePanel from 'ee/security_dashboard/components/shared/mttr_over_time_panel.vue';
import RiskScorePanel from 'ee/security_dashboard/components/shared/risk_score_panel.vue';
import SecurityDashboardDescription from 'ee/security_dashboard/components/shared/security_dashboard_description.vue';
import PdfExportButton from 'ee/security_dashboard/components/shared/pdf_export_button.vue';

Vue.use(VueApollo);

jest.mock('~/alert');

const securityAttributeGid = (id) => `gid://gitlab/Security::Attribute/${id}`;

const mockSecurityCategoriesResponse = {
  data: {
    group: {
      __typename: 'Group',
      id: 'gid://gitlab/Group/1',
      securityCategories: [
        {
          __typename: 'SecurityCategory',
          id: 1,
          name: 'Business Impact',
          description: 'Business impact category',
          multipleSelection: false,
          editableState: 'PARTIALLY_EDITABLE',
          templateType: 'BUSINESS_IMPACT',
          securityAttributes: [
            {
              __typename: 'SecurityAttribute',
              id: 1,
              name: 'Critical',
              color: '#ff0000',
              description: 'Critical impact',
            },
            {
              __typename: 'SecurityAttribute',
              id: 2,
              name: 'High',
              color: '#ff6600',
              description: 'High impact',
            },
          ],
        },
        {
          __typename: 'SecurityCategory',
          id: 2,
          name: 'Custom',
          description: 'Custom category',
          multipleSelection: true,
          editableState: 'EDITABLE',
          templateType: null,
          securityAttributes: [
            {
              __typename: 'SecurityAttribute',
              id: 13,
              name: 'Internal',
              color: '#0000ff',
              description: 'Internal only',
            },
          ],
        },
      ],
    },
  },
};

describe('Group Security Dashboard (new version) - Component', () => {
  let wrapper;
  let securityCategoriesQueryHandler;

  const mockGroupFullPath = 'group/subgroup';

  const createComponent = ({
    provide = {},
    stubs = {},
    securityCategoriesHandler = jest.fn().mockResolvedValue(mockSecurityCategoriesResponse),
  } = {}) => {
    securityCategoriesQueryHandler = securityCategoriesHandler;
    const mockApollo = createMockApollo([
      [getSecurityCategoriesAndAttributes, securityCategoriesQueryHandler],
    ]);

    wrapper = shallowMountExtended(GroupSecurityDashboard, {
      apolloProvider: mockApollo,
      provide: {
        groupFullPath: mockGroupFullPath,
        glFeatures: {
          securityDashboardMttrChart: true,
          vulnerabilityReportSecurityAttributesFilter: true,
        },
        ...provide,
      },
      stubs,
    });
  };

  const findDashboardLayout = () => wrapper.findComponent(GlDashboardLayout);
  const findDashboardDescription = () => wrapper.findComponent(SecurityDashboardDescription);
  const findFilteredSearch = () => wrapper.findComponent(FilteredSearch);
  const getDashboardConfig = () => findDashboardLayout().props('config');
  const findPanelWithId = (panelId) => getDashboardConfig().panels.find(({ id }) => id === panelId);
  const getVulnerabilitiesOverTimePanel = () => findPanelWithId('vulnerabilities-over-time');
  const getVulnerabilitiesByAgePanel = () => findPanelWithId('vulnerabilities-by-age');
  const getVulnerabilitiesByIdentifierPanel = () =>
    findPanelWithId('vulnerabilities-by-identifier');
  const getAgenticAdoptionFunnelPanel = () => findPanelWithId('agentic-adoption-funnel');
  const getMttrOverTimePanel = () => findPanelWithId('mttr-over-time');
  const getRiskScorePanel = () => findPanelWithId('risk-score');
  const getTitle = () => wrapper.find('h1');
  const findPdfExportButton = () => wrapper.findComponent(PdfExportButton);

  describe('component rendering', () => {
    beforeEach(() => {
      createComponent();
    });
    it('renders the dashboard layout component', () => {
      expect(findDashboardLayout().exists()).toBe(true);
    });

    it('renders the correct title', () => {
      expect(getTitle().text()).toBe('Security dashboard');
    });

    it('renders the description', () => {
      expect(findDashboardDescription().exists()).toBe(true);
    });

    it('renders the risk score panel with the correct configuration', () => {
      const riskScorePanel = getRiskScorePanel();

      expect(riskScorePanel.component).toBe(RiskScorePanel);
      expect(riskScorePanel.componentProps.namespace).toBe('group');
      expect(riskScorePanel.componentProps.filters).toEqual({});
      expect(riskScorePanel.gridAttributes).toEqual({
        width: 5,
        height: 4,
        yPos: 3,
        xPos: 0,
      });
    });

    it('renders the vulnerabilities over time panel with the correct configuration', () => {
      const vulnerabilitiesOverTimePanel = getVulnerabilitiesOverTimePanel();

      expect(vulnerabilitiesOverTimePanel.component).toBe(VulnerabilitiesOverTimePanel);
      expect(vulnerabilitiesOverTimePanel.componentProps.namespace).toBe('group');
      expect(vulnerabilitiesOverTimePanel.gridAttributes).toEqual({
        width: 7,
        height: 4,
        xPos: 5,
        yPos: 3,
      });
    });

    it('renders the severity panels with the correct configuration', () => {
      SEVERITY_LEVELS_KEYS.forEach((severity, index) => {
        const severityPanel = findPanelWithId(severity);

        expect(severityPanel.componentProps).toMatchObject({
          namespace: 'group',
          severity,
          filters: {},
        });
        expect(severityPanel.gridAttributes).toEqual({
          width: 2,
          height: 1,
          yPos: 0,
          xPos: 2 * index,
        });
      });
    });

    it('renders the vulnerabilities by age panel with the correct configuration', () => {
      const vulnerabilitiesByAgePanel = getVulnerabilitiesByAgePanel();

      expect(vulnerabilitiesByAgePanel.component).toBe(VulnerabilitiesByAgePanel);
      expect(vulnerabilitiesByAgePanel.componentProps.namespace).toBe('group');
      expect(vulnerabilitiesByAgePanel.gridAttributes).toEqual({
        width: 6,
        height: 4,
        xPos: 0,
        yPos: 7,
      });
    });

    it('renders the vulnerabilities by identifier panel with the correct configuration', () => {
      const panel = getVulnerabilitiesByIdentifierPanel();

      expect(panel.component).toBe(VulnerabilitiesByIdentifierPanel);
      expect(panel.componentProps.namespace).toBe('group');
      expect(panel.componentProps.filters).toEqual({});
      expect(panel.gridAttributes).toEqual({
        width: 6,
        height: 4,
        yPos: 11,
        xPos: 0,
      });
    });

    it('renders the MTTR over time panel next to the vulnerabilities by age panel', () => {
      const panel = getMttrOverTimePanel();

      expect(panel.component).toBe(MttrOverTimePanel);
      expect(panel.componentProps.namespace).toBe('group');
      expect(panel.componentProps.filters).toEqual({});
      expect(panel.gridAttributes).toEqual({
        width: 6,
        height: 4,
        yPos: 7,
        xPos: 6,
      });
    });

    describe('when the securityDashboardMttrChart feature flag is disabled', () => {
      beforeEach(() => {
        createComponent({ provide: { glFeatures: { securityDashboardMttrChart: false } } });
      });

      it('does not render the MTTR over time panel', () => {
        expect(getMttrOverTimePanel()).toBeUndefined();
      });

      it('keeps the vulnerabilities by identifier panel next to the vulnerabilities by age panel', () => {
        expect(getVulnerabilitiesByIdentifierPanel().gridAttributes).toEqual({
          width: 6,
          height: 4,
          yPos: 7,
          xPos: 6,
        });
      });
    });

    it('renders the panel with the correct configuration', () => {
      const panel = getAgenticAdoptionFunnelPanel();

      expect(panel.component).toBe(AgenticAdoptionFunnelPanel);
      expect(panel.componentProps.namespace).toBe('group');
      expect(panel.componentProps.filters).toEqual({});
      expect(panel.gridAttributes).toEqual({
        width: 12,
        height: 2,
        yPos: 1,
        xPos: 0,
      });
    });

    it('renders the PDF export button', () => {
      createComponent();
      expect(findPdfExportButton().exists()).toBe(true);
    });
  });

  describe('while the security categories load', () => {
    const DashboardLayoutStub = {
      props: ['config'],
      template: `<div>
        <slot name="filters"></slot>
        <div v-for="panel in config.panels" :key="panel.id"><slot name="panel" :panel="panel"></slot></div>
      </div>`,
    };
    const findSecurityAttributeTokens = () =>
      findFilteredSearch()
        .props('tokens')
        .filter(({ type }) => type.startsWith('attribute~'));
    const getPanelFilters = () => getRiskScorePanel().componentProps.filters;

    describe('without security attribute params in the URL', () => {
      beforeEach(() => {
        createComponent({ stubs: { GlDashboardLayout: DashboardLayoutStub } });
      });

      it('renders the filtered search and the panels without waiting', () => {
        expect(securityCategoriesQueryHandler).toHaveBeenCalledTimes(1);
        expect(findFilteredSearch().exists()).toBe(true);
        expect(wrapper.findComponent(RiskScorePanel).exists()).toBe(true);
        expect(wrapper.findComponent(VulnerabilitiesOverTimePanel).exists()).toBe(true);
      });

      it('passes no security attribute tokens', () => {
        expect(findSecurityAttributeTokens()).toEqual([]);
      });
    });

    describe('with security attribute params in the URL', () => {
      const expectedUrlFilters = [
        {
          operator: 'IS_NOT_ONE_OF',
          attributes: [securityAttributeGid(1), securityAttributeGid(2)],
        },
        { operator: 'IS_ONE_OF', attributes: [securityAttributeGid(13)] },
      ];

      beforeEach(() => {
        setWindowLocation('?attribute~custom=13&not[attribute~business_impact]=1,2');
      });

      it('passes disabled placeholder tokens for the URL params', () => {
        createComponent();

        expect(findSecurityAttributeTokens()).toEqual([
          expect.objectContaining({ type: 'attribute~business_impact', disabled: true }),
          expect.objectContaining({ type: 'attribute~custom', disabled: true }),
        ]);
      });

      it('passes the security attribute filters from the URL to the panels before the categories load', async () => {
        createComponent({ stubs: { FilteredSearch } });
        await nextTick();

        expect(getPanelFilters().securityAttributesFilters).toEqual(expectedUrlFilters);
      });

      it('replaces the placeholders with the loaded tokens and keeps the filters', async () => {
        createComponent({ stubs: { FilteredSearch } });
        await waitForPromises();

        expect(findSecurityAttributeTokens()).toEqual([
          expect.objectContaining({
            type: 'attribute~business_impact',
            attributeOptions: [
              expect.objectContaining({ id: '1', text: 'Critical' }),
              expect.objectContaining({ id: '2', text: 'High' }),
            ],
          }),
          expect.objectContaining({
            type: 'attribute~custom',
            attributeOptions: [expect.objectContaining({ id: '13', text: 'Internal' })],
          }),
        ]);
        expect(findSecurityAttributeTokens().some(({ disabled }) => disabled)).toBe(false);
        expect(getPanelFilters().securityAttributesFilters).toEqual(expectedUrlFilters);
      });

      describe('when the categories query returns no categories', () => {
        beforeEach(async () => {
          createComponent({
            stubs: { FilteredSearch },
            securityCategoriesHandler: jest.fn().mockResolvedValue({
              data: {
                group: {
                  ...mockSecurityCategoriesResponse.data.group,
                  securityCategories: [],
                },
              },
            }),
          });
          await waitForPromises();
        });

        it('removes filters for categories confirmed to be unavailable', () => {
          expect(findSecurityAttributeTokens()).toEqual([]);
          expect(getPanelFilters()).not.toHaveProperty('securityAttributesFilters');
          expect(window.location.search).toBe('');
        });
      });

      describe('when the categories query fails', () => {
        beforeEach(async () => {
          createComponent({
            stubs: { FilteredSearch },
            securityCategoriesHandler: jest.fn().mockRejectedValue(new Error('boom')),
          });
          await waitForPromises();
        });

        it('alerts', () => {
          expect(createAlert).toHaveBeenCalledWith({
            message: 'Failed to load Security attributes.',
          });
        });

        it('drops the security attribute tokens and their filters', () => {
          expect(findSecurityAttributeTokens()).toEqual([]);
          expect(getPanelFilters()).not.toHaveProperty('securityAttributesFilters');
        });
      });
    });
  });

  describe('filtered search', () => {
    beforeEach(async () => {
      createComponent();
      await waitForPromises();
    });

    it('gets passed the correct tokens', () => {
      expect(findFilteredSearch().props('tokens')).toMatchObject(
        expect.arrayContaining([
          expect.objectContaining({
            type: 'projectId',
            title: 'Project',
            multiSelect: true,
            unique: true,
            token: ProjectToken,
            operators: OPERATORS_OR,
          }),
          expect.objectContaining({
            type: 'reportType',
            title: 'Report type',
            multiSelect: true,
            unique: true,
            token: ReportTypeToken,
            operators: OPERATORS_OR,
          }),
        ]),
      );
    });

    it('passes the correct reportTypes configuration to the ReportTypeToken', () => {
      const reportTypeToken = findFilteredSearch()
        .props('tokens')
        .find((token) => token.type === 'reportType');

      const expectedReportTypes = {
        ...REPORT_TYPES_WITH_MANUALLY_ADDED,
        ...REPORT_TYPES_WITH_CLUSTER_IMAGE,
        ...REPORT_TYPES_CONTAINER_SCANNING_FOR_REGISTRY,
      };

      expect(reportTypeToken.reportTypes).toEqual(expectedReportTypes);
    });

    it('updates filters when filters-changed event is emitted', async () => {
      const newFilters = { projectId: ['gid://gitlab/Project/123'] };
      findFilteredSearch().vm.$emit('filters-changed', newFilters);
      await nextTick();

      expect(getVulnerabilitiesOverTimePanel().componentProps.filters).toEqual(newFilters);
      expect(getMttrOverTimePanel().componentProps.filters).toEqual(newFilters);
    });

    it('clears filters when empty filters object is emitted', async () => {
      const initialFilters = { projectId: ['gid://gitlab/Project/123'] };
      findFilteredSearch().vm.$emit('filters-changed', initialFilters);
      await nextTick();

      expect(getVulnerabilitiesOverTimePanel().componentProps.filters).toEqual(initialFilters);

      // Clear filters
      findFilteredSearch().vm.$emit('filters-changed', {});
      await nextTick();

      expect(getVulnerabilitiesOverTimePanel().componentProps.filters).toEqual({});
    });

    it('passes filters to the vulnerabilities over time panel', async () => {
      const projectId = ['gid://gitlab/Project/123'];
      findFilteredSearch().vm.$emit('filters-changed', { projectId });
      await nextTick();

      expect(getVulnerabilitiesOverTimePanel().componentProps.filters).toEqual({ projectId });
    });

    describe('Security categories and attributes', () => {
      it('fetches security categories', () => {
        expect(securityCategoriesQueryHandler).toHaveBeenCalledWith({
          fullPath: mockGroupFullPath,
        });
        expect(createAlert).not.toHaveBeenCalled();
      });

      it('includes attribute tokens in the filtered search', () => {
        const tokens = findFilteredSearch().props('tokens');
        const attributeToken = tokens.find((token) => token.type.startsWith('attribute~'));

        expect(attributeToken).toMatchObject({
          type: 'attribute~business_impact',
          title: 'Business Impact',
          multiSelect: true,
          unique: true,
          token: AttributeToken,
          categoryId: 1,
          operators: OPERATORS_OR_NOT,
        });
      });

      it('shows an alert when fetch fails', async () => {
        createComponent({
          securityCategoriesHandler: jest.fn().mockRejectedValue(new Error('Network error')),
        });

        await waitForPromises();

        expect(createAlert).toHaveBeenCalledWith({
          message: 'Failed to load Security attributes.',
        });
      });
    });

    describe('url-params-changed', () => {
      beforeEach(() => {
        jest.spyOn(urlUtils, 'updateHistory');
      });

      afterEach(() => {
        setWindowLocation('');
      });

      it('updates browser URL when url-params-changed is emitted', async () => {
        await waitForPromises();

        findFilteredSearch().vm.$emit('url-params-changed', {
          projectId: '5',
          reportType: 'DAST,SAST',
        });

        expect(urlUtils.updateHistory).toHaveBeenCalledWith({
          url: expect.stringContaining('projectId=5&reportType=DAST,SAST'),
          replace: true,
        });
      });

      it('does not update browser URL when it has not changed', async () => {
        await waitForPromises();

        findFilteredSearch().vm.$emit('url-params-changed', {});

        expect(urlUtils.updateHistory).not.toHaveBeenCalled();
      });
    });
  });

  describe('attribute tokens for the vulnerability report links', () => {
    // Observes what the page provides, in place of the filter bar, which is rendered by the same slot.
    const InjectedChild = {
      inject: { attributeTokens: { default: null } },
      computed: {
        providedTokens() {
          return this.attributeTokens.map(({ type, attributeOptions }) => ({
            type,
            attributeIds: attributeOptions.map(({ id }) => id),
          }));
        },
      },
      template: '<div data-testid="injected-child">{{ JSON.stringify(providedTokens) }}</div>',
    };
    const getProvidedTokens = () => JSON.parse(wrapper.findByTestId('injected-child').text());

    describe('when the vulnerabilityReportSecurityAttributesFilter feature flag is enabled', () => {
      beforeEach(async () => {
        createComponent({ stubs: { FilteredSearch: InjectedChild } });
        await waitForPromises();
      });

      it('provides a token for each loaded category with its attribute IDs', () => {
        expect(getProvidedTokens()).toEqual([
          { type: 'attribute~business_impact', attributeIds: ['1', '2'] },
          { type: 'attribute~custom', attributeIds: ['13'] },
        ]);
      });
    });

    describe('with security attribute params in the URL, before the categories load', () => {
      beforeEach(() => {
        setWindowLocation('?attribute~custom=13&not[attribute~business_impact]=1,2');
        createComponent({ stubs: { FilteredSearch: InjectedChild } });
      });

      afterEach(() => {
        setWindowLocation('');
      });

      it('provides the URL attribute IDs for the report links', () => {
        expect(getProvidedTokens()).toEqual([
          { type: 'attribute~business_impact', attributeIds: ['1', '2'] },
          { type: 'attribute~custom', attributeIds: ['13'] },
        ]);
      });
    });

    describe('when the vulnerabilityReportSecurityAttributesFilter feature flag is disabled', () => {
      beforeEach(async () => {
        createComponent({
          stubs: { FilteredSearch: InjectedChild },
          provide: {
            glFeatures: {
              securityDashboardMttrChart: true,
              vulnerabilityReportSecurityAttributesFilter: false,
            },
          },
        });
        await waitForPromises();
      });

      it('provides no tokens', () => {
        expect(getProvidedTokens()).toEqual([]);
      });
    });
  });
});
