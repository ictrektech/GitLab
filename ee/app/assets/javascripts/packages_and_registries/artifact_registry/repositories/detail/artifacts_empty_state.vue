<script>
import emptyStateSvgPath from '@gitlab/svgs/dist/illustrations/empty-state/empty-package-md.svg';
import { GlEmptyState, GlLink, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import {
  REPOSITORY_KIND_HOSTED,
  REPOSITORY_KIND_REMOTE,
  SETUP_SECTION_INSTALL,
  SETUP_SECTION_PUBLISH,
  SETUP_TOOLS,
} from '../../constants';
import { buildRepositoryClientUrl, isContainerFormat } from '../../utils';
import SnippetCodeBlock from '../../components/snippet_code_block.vue';
import { setupSnippetSections } from './setup_instructions/snippets';
import ToolSelector from './setup_instructions/tool_selector.vue';

const hasCode = (blocks) => blocks.some(({ code }) => code);

const toSteps = (blocks) =>
  blocks.reduce((steps, block) => {
    const current = steps.at(-1);

    if (current && !block.startsStep && !(block.code && hasCode(current))) {
      return [...steps.slice(0, -1), [...current, block]];
    }

    return [...steps, [block]];
  }, []);

export default {
  name: 'ArtifactRegistryArtifactsEmptyState',
  components: {
    GlEmptyState,
    GlLink,
    GlSprintf,
    SnippetCodeBlock,
    ToolSelector,
  },
  inject: ['slug', 'clientBaseUrl'],
  props: {
    name: {
      type: String,
      required: true,
    },
    format: {
      type: String,
      required: true,
    },
    kind: {
      type: String,
      required: false,
      default: REPOSITORY_KIND_HOSTED,
    },
  },
  data() {
    return {
      selectedTool: null,
    };
  },
  computed: {
    readsImages() {
      return isContainerFormat(this.format);
    },
    isRemote() {
      return this.kind === REPOSITORY_KIND_REMOTE;
    },
    title() {
      const { i18n } = this.$options;

      if (this.isRemote) {
        return this.readsImages ? i18n.remoteImagesTitle : i18n.remotePackagesTitle;
      }

      return this.readsImages ? i18n.imagesTitle : i18n.packagesTitle;
    },
    description() {
      const { i18n } = this.$options;

      if (this.isRemote) {
        return this.readsImages ? i18n.remoteImagesDescription : i18n.remotePackagesDescription;
      }

      return this.readsImages ? i18n.imagesDescription : i18n.packagesDescription;
    },
    tools() {
      return SETUP_TOOLS[this.format] ?? [];
    },
    activeTool() {
      const selected = this.tools.find(({ value }) => value === this.selectedTool);

      return selected?.value ?? this.tools[0]?.value ?? '';
    },
    repositoryUrl() {
      const { clientBaseUrl, slug, format, name } = this;

      return buildRepositoryClientUrl({ clientBaseUrl, slug, format, name });
    },
    steps() {
      const { format, kind, isRemote, activeTool: tool, slug, name, repositoryUrl } = this;

      const [usageSection, ...setupSections] = setupSnippetSections({
        format,
        kind,
        tool,
        section: isRemote ? SETUP_SECTION_INSTALL : SETUP_SECTION_PUBLISH,
        slug,
        name,
        repositoryUrl,
      });

      if (!usageSection) return [];

      return [...setupSections, usageSection].flatMap(({ blocks }) => toSteps(blocks));
    },
  },
  i18n: {
    packagesTitle: s__('ArtifactRegistry|There are no packages in this repository yet'),
    imagesTitle: s__('ArtifactRegistry|There are no images in this repository yet'),
    packagesDescription: s__('ArtifactRegistry|Publish your first package to get started.'),
    imagesDescription: s__('ArtifactRegistry|Publish your first image to get started.'),
    remotePackagesTitle: s__(
      'ArtifactRegistry|There are no packages cached in this repository yet',
    ),
    remoteImagesTitle: s__('ArtifactRegistry|There are no images cached in this repository yet'),
    remotePackagesDescription: s__(
      'ArtifactRegistry|Configure your client to use this remote repository. Packages will appear here as you pull them.',
    ),
    remoteImagesDescription: s__(
      'ArtifactRegistry|Configure your client to use this remote repository. Images will appear here as you pull them.',
    ),
    cliCommands: s__('ArtifactRegistry|CLI commands'),
  },
  emptyStateSvgPath,
};
</script>

<template>
  <div>
    <gl-empty-state
      :svg-path="$options.emptyStateSvgPath"
      :title="title"
      :description="description"
    />

    <section
      v-if="steps.length"
      class="gl-mx-auto gl-my-0 gl-max-w-xl gl-text-center"
      data-testid="empty-state-setup"
    >
      <div class="gl-mb-4 gl-flex gl-items-center gl-justify-center gl-gap-3">
        <h3 class="gl-heading-4 gl-mb-0">{{ $options.i18n.cliCommands }}</h3>

        <tool-selector :format="format" :selected="activeTool" @select="selectedTool = $event" />
      </div>

      <ol class="gl-mb-0 gl-pl-5 gl-text-left">
        <li
          v-for="(step, index) in steps"
          :key="index"
          class="gl-mb-4"
          data-testid="empty-state-step"
        >
          <div v-for="(block, blockIndex) in step" :key="blockIndex">
            <p class="gl-mb-3">
              <gl-sprintf :message="block.text">
                <template #code="{ content }">
                  <code>{{ content }}</code>
                </template>
                <template #link="{ content }">
                  <gl-link :href="block.link" target="_blank">{{ content }}</gl-link>
                </template>
              </gl-sprintf>
            </p>

            <snippet-code-block
              v-if="block.code"
              :snippet="block.code"
              :copy-text="block.copyText"
              class="gl-mb-3"
            />
          </div>
        </li>
      </ol>
    </section>
  </div>
</template>
