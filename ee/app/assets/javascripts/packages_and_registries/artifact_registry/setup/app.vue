<script>
import { artifactRegistryRepositoriesOrganizationPath } from 'ee/lib/utils/path_helpers/organizations';
import { refreshCurrentPageWithAlerts, visitUrlWithAlerts } from '~/lib/utils/url_utility';
import { s__, sprintf } from '~/locale';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import SetupForm from './setup_form.vue';

const ACTIVATED_ALERT_ID = 'artifact-registry-activated';
const ALREADY_ACTIVATED_ALERT_ID = 'artifact-registry-already-activated';

export default {
  name: 'ArtifactRegistrySetupApp',
  i18n: {
    heading: s__('ArtifactRegistry|Set up Artifact registry'),
    description: s__(
      'ArtifactRegistry|A unified registry for artifacts across all projects and groups in your organization. To get started, choose a registry handle.',
    ),
    activatedTitle: s__('ArtifactRegistry|Artifact registry set up successfully'),
    activated: s__(
      'ArtifactRegistry|Create your first repository to start publishing and pulling artifacts.',
    ),
    alreadyActivatedTitle: s__('ArtifactRegistry|Artifact registry is already enabled'),
    alreadyActivated: s__(
      'ArtifactRegistry|Your organization is using the handle %{handle}. The handle you entered was not claimed.',
    ),
  },
  components: {
    PageHeading,
    SetupForm,
  },
  inject: ['organizationPath'],
  methods: {
    onSuccess({ slug }) {
      visitUrlWithAlerts(
        artifactRegistryRepositoriesOrganizationPath(this.organizationPath, slug),
        [
          {
            id: ACTIVATED_ALERT_ID,
            title: this.$options.i18n.activatedTitle,
            message: this.$options.i18n.activated,
            variant: 'success',
            dismissible: true,
          },
        ],
      );
    },
    // Reloads the landing route rather than picking a destination: the server answers by registry state.
    onConflict({ slug }) {
      refreshCurrentPageWithAlerts([
        {
          id: ALREADY_ACTIVATED_ALERT_ID,
          title: this.$options.i18n.alreadyActivatedTitle,
          message: sprintf(this.$options.i18n.alreadyActivated, { handle: slug }),
          variant: 'info',
          dismissible: true,
        },
      ]);
    },
  },
};
</script>

<template>
  <div data-testid="artifact-registry-setup">
    <page-heading :heading="$options.i18n.heading">
      <template #description>{{ $options.i18n.description }}</template>
    </page-heading>

    <setup-form @success="onSuccess" @conflict="onConflict" />
  </div>
</template>
