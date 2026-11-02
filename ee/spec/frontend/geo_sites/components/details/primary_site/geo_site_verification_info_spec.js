import { GlCard, GlPopover, GlLink, GlIcon } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
// eslint-disable-next-line no-restricted-imports
import Vuex from 'vuex';
import HelpIcon from '~/vue_shared/components/help_icon/help_icon.vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import GeoSiteProgressBar from 'ee/geo_sites/components/details/geo_site_progress_bar.vue';
import GeoSiteReplicableTitle from 'ee/geo_sites/components/details/geo_site_replicable_title.vue';
import GeoSiteVerificationInfo from 'ee/geo_sites/components/details/primary_site/geo_site_verification_info.vue';
import { HELP_INFO_URL } from 'ee/geo_sites/constants';
import {
  MOCK_PRIMARY_SITE,
  MOCK_VERIFICATION_INFO,
  MOCK_UPLOADS_GROUP_TYPE,
  MOCK_UPLOAD_PARTITION_TYPES,
} from 'ee_jest/geo_sites/mock_data';

Vue.use(Vuex);

describe('GeoSiteVerificationInfo', () => {
  let wrapper;

  const defaultProps = {
    site: MOCK_PRIMARY_SITE,
  };

  const createComponent = ({ verificationInfo = MOCK_VERIFICATION_INFO } = {}) => {
    const store = new Vuex.Store({
      getters: {
        groupedVerificationInfo: () => () => verificationInfo,
      },
    });

    wrapper = shallowMountExtended(GeoSiteVerificationInfo, {
      store,
      propsData: defaultProps,
      stubs: { GlCard, HelpIcon },
    });
  };

  const findGlCard = () => wrapper.findComponent(GlCard);
  const findGlIcon = () => wrapper.findComponent(HelpIcon);
  const findGlPopover = () => wrapper.findComponent(GlPopover);
  const findGlPopoverLink = () => findGlPopover().findComponent(GlLink);
  const findGeoSiteProgressBarLinks = () =>
    wrapper.findAllComponentsByTestId('verification-bar-data-management-link');
  const findGeoSiteProgressBarGroups = () => wrapper.findAllByTestId('verification-bar-group');
  const findGroupToggle = () => wrapper.findComponent(GeoSiteReplicableTitle);
  const findGeoSiteProgressBarTitles = () => wrapper.findAllByTestId('verification-bar-title');
  const findGeoSiteProgressBars = () => wrapper.findAllComponents(GeoSiteProgressBar);

  describe('template', () => {
    describe('always', () => {
      beforeEach(() => {
        createComponent();
      });

      it('renders the details card', () => {
        expect(findGlCard().exists()).toBe(true);
      });

      it('renders the question icon correctly', () => {
        expect(findGlIcon().exists()).toBe(true);
        expect(findGlIcon().attributes('name')).toBe('question-o');
      });

      it('renders the GlPopover always', () => {
        expect(findGlPopover().exists()).toBe(true);
      });

      it('renders the popover link correctly', () => {
        expect(findGlPopoverLink().exists()).toBe(true);
        expect(findGlPopoverLink().attributes('href')).toBe(HELP_INFO_URL);
      });

      it('renders a progress bar for each verification replicable', () => {
        expect(findGeoSiteProgressBars()).toHaveLength(MOCK_VERIFICATION_INFO.length);
      });
    });

    describe('progress bars', () => {
      beforeEach(() => {
        createComponent();
      });

      it('renders progress bar containers as links', () => {
        expect(findGeoSiteProgressBarGroups()).toHaveLength(0);
        expect(findGeoSiteProgressBarLinks()).toHaveLength(MOCK_VERIFICATION_INFO.length);
      });

      it('renders each progress bar link correctly', () => {
        expect(findGeoSiteProgressBarLinks().wrappers.map((w) => w.props('href'))).toStrictEqual(
          MOCK_VERIFICATION_INFO.map((vI) => vI.dataManagementUrl),
        );
      });

      it('renders progress bar titles correctly', () => {
        expect(findGeoSiteProgressBarTitles().wrappers.map((w) => w.text())).toStrictEqual(
          MOCK_VERIFICATION_INFO.map((vI) => vI.titlePlural),
        );
      });

      it('does render GlIcon for each container', () => {
        expect(
          findGeoSiteProgressBarLinks().wrappers.map((w) => w.findComponent(GlIcon).exists()),
        ).toStrictEqual(MOCK_VERIFICATION_INFO.map(() => true));
      });
    });

    describe('with a replicable group', () => {
      const childInfo = (replicable, values) => ({
        namePlural: replicable.namePlural,
        titlePlural: replicable.titlePlural,
        dataManagementUrl: replicable.dataManagementUrl,
        values,
      });
      const MOCK_GROUP_INFO = {
        namePlural: MOCK_UPLOADS_GROUP_TYPE.namePlural,
        titlePlural: MOCK_UPLOADS_GROUP_TYPE.titlePlural,
        values: { total: 20, success: 20, failed: 0 },
        children: [
          childInfo(MOCK_UPLOAD_PARTITION_TYPES[0], null),
          childInfo(MOCK_UPLOAD_PARTITION_TYPES[1], { total: 20, success: 20, failed: 0 }),
        ],
      };

      beforeEach(() => {
        createComponent({ verificationInfo: [MOCK_VERIFICATION_INFO[1], MOCK_GROUP_INFO] });
      });

      it('renders the group as a collapsed non-link row with an aggregated progress bar', () => {
        expect(findGeoSiteProgressBarLinks()).toHaveLength(1);
        expect(findGeoSiteProgressBarGroups()).toHaveLength(1);
        expect(findGroupToggle().props()).toMatchObject({ item: MOCK_GROUP_INFO, expanded: false });
        expect(
          findGeoSiteProgressBarGroups().at(0).findComponent(GeoSiteProgressBar).props('values'),
        ).toStrictEqual({ total: 20, success: 20, failed: 0 });
      });

      describe('when the group is expanded', () => {
        beforeEach(() => {
          findGroupToggle().vm.$emit('toggle');
        });

        it('renders an indented link per child after the group row', () => {
          expect(findGroupToggle().props('expanded')).toBe(true);
          expect(findGeoSiteProgressBarLinks().wrappers.map((w) => w.props('href'))).toStrictEqual([
            MOCK_VERIFICATION_INFO[1].dataManagementUrl,
            MOCK_UPLOAD_PARTITION_TYPES[0].dataManagementUrl,
            MOCK_UPLOAD_PARTITION_TYPES[1].dataManagementUrl,
          ]);
          expect(
            findGeoSiteProgressBarLinks().wrappers.map((w) => w.classes('gl-ml-6')),
          ).toStrictEqual([false, true, true]);
        });

        describe('when the group is toggled again', () => {
          beforeEach(async () => {
            findGroupToggle().vm.$emit('toggle');
            await nextTick();
          });

          it('collapses the group and removes the child links', () => {
            expect(findGroupToggle().props('expanded')).toBe(false);
            expect(
              findGeoSiteProgressBarLinks().wrappers.map((w) => w.props('href')),
            ).toStrictEqual([MOCK_VERIFICATION_INFO[1].dataManagementUrl]);
          });
        });
      });
    });
  });
});
