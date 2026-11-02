import { defineStore } from 'pinia';
import { normalizeHeaders } from '@gitlab/frontend-utils';
import Api from '~/api';
import { createAlert } from '~/alert';
import { parseIntPagination } from '~/lib/utils/common_utils';
import { __ } from '~/locale';

export const useSamlMembers = defineStore('samlMembers', {
  state() {
    return {
      isInitialLoadInProgress: true,
      groupId: null,
      pageInfo: {
        perPage: 10,
        page: 1,
        total: 20,
        totalPages: 1,
        nextPage: 0,
        previousPage: 0,
      },
      members: [],
    };
  },
  actions: {
    setInitialState({ groupId }) {
      this.groupId = groupId;
    },
    fetchPage(newPage) {
      return Api.groupMembers(this.groupId, {
        with_saml_identity: 'true',
        page: newPage || this.pageInfo.page,
        per_page: this.pageInfo.perPage,
      })
        .then((response) => {
          const { headers, data } = response;
          this.isInitialLoadInProgress = false;
          this.members = data.map(
            ({ group_saml_identity: identity, group_scim_identity: scimIdentity, ...item }) => ({
              ...item,
              identity: identity ? identity.extern_uid : null,
              scim_identity: scimIdentity ? scimIdentity.extern_uid : null,
            }),
          );
          this.pageInfo = parseIntPagination(normalizeHeaders(headers));
        })
        .catch(() => {
          createAlert({
            message: __('An error occurred while loading group members.'),
          });
        });
    },
  },
});
