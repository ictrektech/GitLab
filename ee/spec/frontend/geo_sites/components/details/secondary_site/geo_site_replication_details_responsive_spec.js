import { GlLink } from '@gitlab/ui';
import { shallowMountExtended, extendedWrapper } from 'helpers/vue_test_utils_helper';
import GeoSiteProgressBar from 'ee/geo_sites/components/details/geo_site_progress_bar.vue';
import GeoSiteReplicableTitle from 'ee/geo_sites/components/details/geo_site_replicable_title.vue';
import GeoSiteReplicationDetailsResponsive from 'ee/geo_sites/components/details/secondary_site/geo_site_replication_details_responsive.vue';

describe('GeoSiteReplicationDetailsResponsive', () => {
  let wrapper;

  const defaultProps = {
    replicationItems: [],
    siteId: 0,
  };

  const createComponent = (props, slots) => {
    wrapper = shallowMountExtended(GeoSiteReplicationDetailsResponsive, {
      propsData: {
        ...defaultProps,
        ...props,
      },
      scopedSlots: {
        ...slots,
      },
      stubs: { GeoSiteReplicableTitle },
    });
  };

  const findReplicationDetailsHeader = () => wrapper.findByTestId('replication-details-header');
  const findReplicationDetailsItems = () => wrapper.findAllByTestId('replication-details-item');
  const findFirstReplicationDetailsItemSyncStatus = () =>
    extendedWrapper(findReplicationDetailsItems().at(0)).findByTestId('sync-status');
  const findFirstReplicationDetailsItemVerifStatus = () =>
    extendedWrapper(findReplicationDetailsItems().at(0)).findByTestId('verification-status');
  const findReplicableComponent = () => wrapper.findByTestId('replicable-component');
  const findReplicableComponentLink = () => findReplicableComponent().findComponent(GlLink);
  const findGroupToggle = () => wrapper.findComponent(GeoSiteReplicableTitle);

  describe('template', () => {
    describe('with default slots', () => {
      describe('always', () => {
        beforeEach(() => {
          createComponent();
        });

        it('renders the replication details header', () => {
          expect(findReplicationDetailsHeader().exists()).toBe(true);
        });

        it('renders the replication details header items correctly', () => {
          expect(findReplicationDetailsHeader().text()).toContain(
            'Data type Component Synchronization status Verification status',
          );
        });
      });

      describe('replication details', () => {
        describe('when null', () => {
          beforeEach(() => {
            createComponent({ replicationItems: null });
          });

          it('does not render any replicable items', () => {
            expect(findReplicationDetailsItems()).toHaveLength(0);
          });
        });
      });

      describe.each`
        description                    | replicationItems
        ${'with no data'}              | ${[{ dataTypeTitle: 'Test Title', namePlural: 'test_components', titlePlural: 'Test Component', syncValues: null, verificationValues: null }]}
        ${'with no verification data'} | ${[{ dataTypeTitle: 'Test Title', namePlural: 'test_components', titlePlural: 'Test Component', syncValues: { total: 100, success: 0 }, verificationValues: null }]}
        ${'with no sync data'}         | ${[{ dataTypeTitle: 'Test Title', namePlural: 'test_components', titlePlural: 'Test Component', syncValues: null, verificationValues: { total: 50, success: 50 } }]}
        ${'with all data'}             | ${[{ dataTypeTitle: 'Test Title', namePlural: 'test_components', titlePlural: 'Test Component', syncValues: { total: 100, success: 0 }, verificationValues: { total: 50, success: 50 } }]}
      `('$description', ({ replicationItems }) => {
        beforeEach(() => {
          createComponent({ replicationItems, siteId: 42 });
        });

        it('always renders sync progress bar component with correct target', () => {
          expect(
            findFirstReplicationDetailsItemSyncStatus()
              .findComponent(GeoSiteProgressBar)
              .props('target'),
          ).toBe('sync-progress-42-test_components');
        });

        it('always renders verification progress bar component with correct target', () => {
          expect(
            findFirstReplicationDetailsItemVerifStatus()
              .findComponent(GeoSiteProgressBar)
              .props('target'),
          ).toBe('verification-progress-42-test_components');
        });
      });

      describe('component links', () => {
        describe('with replicationView and syncValues', () => {
          const MOCK_REPLICATION_ITEM = {
            titlePlural: 'Test Component',
            replicationView: 'https://test.domain/path',
            syncValues: { total: 100, success: 100 },
          };

          beforeEach(() => {
            createComponent({ replicationItems: [MOCK_REPLICATION_ITEM] });
          });

          it('renders replicable component title', () => {
            expect(findReplicableComponent().text()).toBe(MOCK_REPLICATION_ITEM.titlePlural);
          });

          it(`renders GlLink to secondary replication view`, () => {
            expect(findReplicableComponentLink().exists()).toBe(true);
            expect(findReplicableComponentLink().attributes('href')).toBe(
              MOCK_REPLICATION_ITEM.replicationView,
            );
          });
        });

        describe('without replicationView', () => {
          const MOCK_REPLICATION_ITEM = { titlePlural: 'Test Component', replicationView: null };

          beforeEach(() => {
            createComponent({ replicationItems: [MOCK_REPLICATION_ITEM] });
          });

          it('renders replicable component title', () => {
            expect(findReplicableComponent().text()).toBe(MOCK_REPLICATION_ITEM.titlePlural);
          });

          it(`does not render GlLink to secondary replication view`, () => {
            expect(findReplicableComponentLink().exists()).toBe(false);
          });
        });
      });
    });

    describe('with a replicable group', () => {
      const MOCK_GROUP_ITEM = {
        dataTypeTitle: 'File',
        namePlural: 'uploads',
        titlePlural: 'Uploads',
        replicationView: null,
        syncValues: { total: 30, success: 20, failed: 5 },
        verificationValues: null,
        children: [
          {
            dataTypeTitle: 'File',
            namePlural: 'group_uploads',
            titlePlural: 'Group Uploads',
            replicationView: '/admin/geo/sites/42/replication/group_uploads',
            syncValues: { total: 10, success: 10, failed: 0 },
            verificationValues: null,
          },
          {
            dataTypeTitle: 'File',
            namePlural: 'project_uploads',
            titlePlural: 'Project Uploads',
            replicationView: '/admin/geo/sites/42/replication/project_uploads',
            syncValues: { total: 20, success: 10, failed: 5 },
            verificationValues: null,
          },
        ],
      };

      describe('when the group is collapsed', () => {
        beforeEach(() => {
          createComponent({ replicationItems: [MOCK_GROUP_ITEM], siteId: 42 });
        });

        it('renders only the group row', () => {
          expect(findReplicationDetailsItems()).toHaveLength(1);
          expect(findGroupToggle().props()).toMatchObject({
            item: MOCK_GROUP_ITEM,
            expanded: false,
          });
        });

        it('emits toggle-group with the item when the group is toggled', () => {
          findGroupToggle().vm.$emit('toggle');

          expect(wrapper.emitted('toggle-group')).toStrictEqual([[MOCK_GROUP_ITEM]]);
        });
      });

      describe('when the group is expanded', () => {
        beforeEach(() => {
          createComponent({
            replicationItems: [MOCK_GROUP_ITEM],
            siteId: 42,
            expandedGroups: ['uploads'],
          });
        });

        it('renders the group row followed by an indented row per child', () => {
          expect(findReplicationDetailsItems()).toHaveLength(3);
          expect(findGroupToggle().props('expanded')).toBe(true);
          expect(
            findReplicationDetailsItems().wrappers.map((w) => w.classes('gl-ml-6')),
          ).toStrictEqual([false, true, true]);
        });

        it('renders a sync progress bar per child with its own target', () => {
          expect(
            findReplicationDetailsItems().wrappers.map((item) =>
              extendedWrapper(item)
                .findByTestId('sync-status')
                .findComponent(GeoSiteProgressBar)
                .props('target'),
            ),
          ).toStrictEqual([
            'sync-progress-42-uploads',
            'sync-progress-42-group_uploads',
            'sync-progress-42-project_uploads',
          ]);
        });
      });
    });

    describe('with custom title slot', () => {
      beforeEach(() => {
        const title =
          '<template #title="{ translations }"><span>{{ translations.component }} {{ translations.status }}</span></template>';
        createComponent(null, { title });
      });

      it('renders the replication details header', () => {
        expect(findReplicationDetailsHeader().exists()).toBe(true);
      });

      it('renders the replication details header with access to the translations prop', () => {
        expect(findReplicationDetailsHeader().text()).toBe('Component Status');
      });
    });

    describe('with custom default slot', () => {
      beforeEach(() => {
        const defaultSlot =
          '<template #default="{ item, translations }"><span>{{ item.titlePlural }} {{ item.dataTypeTitle }} {{ translations.status }}</span></template>';
        createComponent(
          { replicationItems: [{ titlePlural: 'Test Component', dataTypeTitle: 'Test Title' }] },
          { default: defaultSlot },
        );
      });

      it('renders the replication details items section', () => {
        expect(findReplicationDetailsItems().exists()).toBe(true);
      });

      it('renders the replication details items section with access to the item and translations prop', () => {
        expect(findReplicationDetailsItems().at(0).text()).toBe('Test Component Test Title Status');
      });
    });
  });
});
