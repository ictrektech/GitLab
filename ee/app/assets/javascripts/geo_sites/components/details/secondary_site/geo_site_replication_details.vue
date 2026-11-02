<script>
import { GlButton } from '@gitlab/ui';
// eslint-disable-next-line no-restricted-imports
import { mapGetters } from 'vuex';
import { toggleExpandedGroup } from 'ee/geo_sites/utils';
import { joinPaths } from '~/lib/utils/url_utility';
import GeoSiteReplicableTitle from '../geo_site_replicable_title.vue';
import GeoSiteReplicationDetailsResponsive from './geo_site_replication_details_responsive.vue';
import GeoSiteReplicationStatusMobile from './geo_site_replication_status_mobile.vue';

export default {
  name: 'GeoSiteReplicationDetails',
  components: {
    GlButton,
    GeoSiteReplicableTitle,
    GeoSiteReplicationDetailsResponsive,
    GeoSiteReplicationStatusMobile,
  },
  props: {
    site: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      collapsed: false,
      // Shared by the desktop and mobile instances so a resize does not desync them
      expandedGroups: [],
    };
  },
  computed: {
    ...mapGetters(['groupedVerificationInfo', 'groupedSyncInfo', 'groupedReplicableTypes']),
    replicationItems() {
      return this.buildReplicationItems(
        this.groupedReplicableTypes,
        this.groupedSyncInfo(this.site.id),
        this.groupedVerificationInfo(this.site.id),
      );
    },
    chevronIcon() {
      return this.collapsed ? 'chevron-right' : 'chevron-down';
    },
  },
  methods: {
    collapseSection() {
      this.collapsed = !this.collapsed;
    },
    toggleGroup(item) {
      this.expandedGroups = toggleExpandedGroup(this.expandedGroups, item);
    },
    buildReplicationItems(replicableTypes, syncInfoData, verificationInfoData) {
      return replicableTypes.map(
        ({ namePlural, titlePlural, dataTypeTitle, replicationEnabled, children }) => {
          const replicableSyncInfo = syncInfoData.find((r) => r.namePlural === namePlural);

          const replicableVerificationInfo = verificationInfoData.find(
            (r) => r.namePlural === namePlural,
          );

          const item = {
            namePlural,
            dataTypeTitle,
            titlePlural,
            syncValues: replicableSyncInfo?.values,
            verificationValues: replicableVerificationInfo?.values,
            replicationView:
              replicationEnabled && !children ? this.getReplicationView(namePlural) : null,
          };

          if (!children) {
            return item;
          }

          return {
            ...item,
            children: this.buildReplicationItems(
              children,
              replicableSyncInfo?.children || [],
              replicableVerificationInfo?.children || [],
            ),
          };
        },
      );
    },
    getReplicationView(namePlural) {
      return joinPaths(
        gon.relative_url_root || '/',
        `/admin/geo/sites/${this.site.id}/replication/${namePlural}`,
      );
    },
  },
};
</script>

<template>
  <div>
    <div class="gl-border-t gl-border-b gl-py-5">
      <gl-button
        class="gl-mr-1 !gl-p-0"
        category="tertiary"
        variant="confirm"
        :icon="chevronIcon"
        @click="collapseSection"
      >
        {{ s__('Geo|Replication Details') }}
      </gl-button>
    </div>
    <div v-if="!collapsed">
      <geo-site-replication-details-responsive
        class="gl-hidden @md/panel:gl-block"
        :site-id="site.id"
        :replication-items="replicationItems"
        :expanded-groups="expandedGroups"
        data-testid="geo-replication-details-desktop"
        @toggle-group="toggleGroup"
      />
      <geo-site-replication-details-responsive
        class="@md/panel:!gl-hidden"
        :site-id="site.id"
        :replication-items="replicationItems"
        :expanded-groups="expandedGroups"
        data-testid="geo-replication-details-mobile"
        @toggle-group="toggleGroup"
      >
        <template #title="{ translations }">
          <span class="gl-font-bold">{{ translations.component }}</span>
          <span class="gl-font-bold">{{ translations.status }}</span>
        </template>
        <template #default="{ item, translations, expanded }">
          <div class="gl-mr-5" data-testid="replicable-component">
            <geo-site-replicable-title
              :item="item"
              :expanded="expanded"
              @toggle="toggleGroup(item)"
            />
          </div>
          <geo-site-replication-status-mobile :item="item" :translations="translations" />
        </template>
      </geo-site-replication-details-responsive>
    </div>
  </div>
</template>
