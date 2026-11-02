import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createDefaultClient from '~/lib/graphql';

Vue.use(VueApollo);

// The policies, catalogs and evaluations queries run concurrently and all write
// the container's policyStore, which has no id to normalize on — without merge,
// Apollo replaces the earlier write and drops its fields.
//
// A denied read is null, which mergeObjects would also let replace the other
// query's write, so a page whose policies read succeeded would show a
// permission error. The experiment flag is read per request, so the two reads
// of one page load can disagree. Keeping the existing object means rows a
// revoke should hide stay until the page reloads; that is the cheaper failure.
const keepUnlessFirstWrite = (existing, incoming, { mergeObjects }) =>
  incoming === null && existing ? existing : mergeObjects(existing, incoming);

export const typePolicies = {
  Organization: { fields: { policyStore: { merge: keepUnlessFirstWrite } } },
  Group: { fields: { policyStore: { merge: keepUnlessFirstWrite } } },
  Project: { fields: { policyStore: { merge: keepUnlessFirstWrite } } },
};

export default () =>
  new VueApollo({ defaultClient: createDefaultClient({}, { cacheConfig: { typePolicies } }) });
