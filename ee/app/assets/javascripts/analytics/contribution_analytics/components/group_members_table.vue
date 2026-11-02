<script>
import { GlTable, GlLink } from '@gitlab/ui';
import { TABLE_COLUMNS } from '../constants';

export default {
  name: 'GroupMembersTable',
  columns: TABLE_COLUMNS,
  components: {
    GlTable,
    GlLink,
  },
  props: {
    contributions: {
      type: Array,
      required: true,
    },
  },
  data() {
    return {
      sortBy: TABLE_COLUMNS[0].key,
      sortDesc: false,
    };
  },
  methods: {
    onSortChanged({ sortBy, sortDesc }) {
      this.sortBy = sortBy;
      this.sortDesc = sortDesc;
    },
  },
};
</script>

<template>
  <div>
    <gl-table
      :items="contributions"
      :fields="$options.columns"
      :sort-by="sortBy"
      :sort-desc="sortDesc"
      stacked="lg"
      @sort-changed="onSortChanged"
    >
      <template
        #cell(user)="{
          item: {
            user: { name, webUrl },
          },
        }"
      >
        <gl-link :href="webUrl" class="gl-font-bold">{{ name }}</gl-link>
      </template>
    </gl-table>
  </div>
</template>
