import ArtifactsEmptyState from './artifacts_empty_state.vue';

export default {
  component: ArtifactsEmptyState,
  title: 'ee/packages_and_registries/artifact_registry/repositories/detail/artifacts_empty_state',
};

const Template =
  (format, kind = 'HOSTED') =>
  () => ({
    components: { ArtifactsEmptyState },
    provide: {
      slug: 'acme',
      clientBaseUrl: 'https://ar.gitlab.com',
    },
    data() {
      return { format, kind };
    },
    template: '<artifacts-empty-state name="my-repository" :format="format" :kind="kind" />',
  });

export const Maven = Template('MAVEN');

export const Npm = Template('NPM');

export const Docker = Template('DOCKER');

export const Oci = Template('OCI');

export const RemoteMaven = Template('MAVEN', 'REMOTE');

export const RemoteNpm = Template('NPM', 'REMOTE');

export const RemoteDocker = Template('DOCKER', 'REMOTE');
