<script>
import { mapActions } from 'pinia';
import { useBillingsSubscription } from '../store';
import SubscriptionTable from './subscription_table.vue';

export default {
  name: 'SubscriptionApp',
  components: {
    SubscriptionTable,
  },
  inject: {
    namespaceId: {
      default: null,
    },
  },
  created() {
    this.setNamespaceId(this.namespaceId);
  },
  methods: {
    ...mapActions(useBillingsSubscription, ['setNamespaceId']),
  },
};
</script>

<template>
  <subscription-table />
</template>
