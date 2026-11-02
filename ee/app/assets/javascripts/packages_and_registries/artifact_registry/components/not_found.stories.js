import NotFound from './not_found.vue';

export default {
  component: NotFound,
  title: 'ee/packages_and_registries/artifact_registry/components/not_found',
};

export const Default = () => ({
  components: { NotFound },
  template: '<not-found />',
});
