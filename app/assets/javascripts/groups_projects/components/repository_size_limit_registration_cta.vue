<script>
import { GlFormGroup, GlFormInput, GlLink, GlSprintf } from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import { FIELD_NAME_PREFIXES } from '~/groups_projects/constants';

export default {
  name: 'RepositorySizeLimitRegistrationCta',
  components: {
    GlFormGroup,
    GlFormInput,
    GlLink,
    GlSprintf,
    HelpPageLink,
  },
  props: {
    // Rails param namespace of the surrounding form, e.g. `project` or `group`.
    fieldNamePrefix: {
      type: String,
      required: true,
      validator: (value) => FIELD_NAME_PREFIXES.includes(value),
    },
    servicePingSettingsPath: {
      type: String,
      required: false,
      default: '',
    },
  },
  computed: {
    inputId() {
      return `${this.fieldNamePrefix}_disabled_repository_size_limit`;
    },
    inputName() {
      return `${this.fieldNamePrefix}[disabled_repository_size_limit]`;
    },
    ctaMessage() {
      return sprintf(s__('RegistrationFeatures|Want to %{feature_title} for free?'), {
        feature_title: s__('RegistrationFeatures|use this feature'),
      });
    },
  },
};
</script>

<template>
  <gl-form-group
    :label="__('Repository size limit (MiB)')"
    :label-for="inputId"
    class="gl-col-md-9"
  >
    <gl-form-input
      :id="inputId"
      type="number"
      :name="inputName"
      disabled
      :min="0"
      data-testid="repository-size-limit-field"
    />
    <template #description>
      <div>
        <span>{{ ctaMessage }}</span>
        <gl-link
          v-if="servicePingSettingsPath"
          :href="servicePingSettingsPath"
          class="js-go-to-service-ping-settings"
          data-testid="service-ping-settings-link"
          >{{
            s__('RegistrationFeatures|Enable Service Ping and register for this feature.')
          }}</gl-link
        >
        <gl-sprintf
          :message="
            s__(
              'RegistrationFeatures|Read more about the %{linkStart}Registration Features Program%{linkEnd}.',
            )
          "
        >
          <template #link="{ content }">
            <help-page-link
              href="administration/settings/usage_statistics"
              anchor="registration-features-program"
              target="_blank"
              data-testid="registration-features-docs-link"
              >{{ content }}</help-page-link
            >
          </template>
        </gl-sprintf>
      </div>
    </template>
  </gl-form-group>
</template>
