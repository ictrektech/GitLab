<script>
import { isGid } from '~/graphql_shared/utils';
import UserTokenFoss from '~/vue_shared/components/filtered_search_bar/tokens/user_token.vue';
import getUsersByUserIdsOrUsernames from 'ee/graphql_shared/queries/get_users_by_user_ids_or_usernames.query.graphql';

// This is a false violation of @gitlab/no-runtime-template-compiler, since it
// extends a valid Vue single file component.
// eslint-disable-next-line @gitlab/no-runtime-template-compiler
export default {
  name: 'TriggeredByToken',
  extends: UserTokenFoss,
  methods: {
    // The token value is the user's global ID (`valueField: 'id'`) so it can be
    // passed straight to `triggeredByUserId`, but the parent matches on
    // username. Match on either so the view slot renders name + avatar.
    // eslint-disable-next-line vue/no-unused-properties -- This component inherits from `UserTokenFoss` which calls `getActiveUser()` internally
    getActiveUser(users, data) {
      return users.find(
        (user) => user.id === data || user.username?.toLowerCase() === String(data).toLowerCase(),
      );
    },
    // A value seeded from the URL is a global ID, which the autocomplete search
    // cannot find, so look that user up by ID to render their name and avatar.
    // eslint-disable-next-line vue/no-unused-properties -- Called by `UserTokenFoss.fetchUsers()`
    fetchUsersBySearchTerm(search) {
      if (!isGid(search)) return UserTokenFoss.methods.fetchUsersBySearchTerm.call(this, search);

      return this.$apollo
        .query({ query: getUsersByUserIdsOrUsernames, variables: { user_ids: [search] } })
        .then(({ data }) => data.users?.nodes || []);
    },
  },
};
</script>
