import { GlEmptyState } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ArtifactsEmptyState from 'ee/packages_and_registries/artifact_registry/repositories/detail/artifacts_empty_state.vue';
import SnippetCodeBlock from 'ee/packages_and_registries/artifact_registry/components/snippet_code_block.vue';
import ToolSelector from 'ee/packages_and_registries/artifact_registry/repositories/detail/setup_instructions/tool_selector.vue';
import { REPOSITORY_KIND_REMOTE } from 'ee/packages_and_registries/artifact_registry/constants';
import { CLIENT_BASE_URL, SLUG } from '../../mock_data';

describe('ArtifactRegistryArtifactsEmptyState', () => {
  let wrapper;

  const findEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findSetup = () => wrapper.findByTestId('empty-state-setup');
  const findSelector = () => wrapper.findComponent(ToolSelector);
  const findSteps = () => wrapper.findAllByTestId('empty-state-step');
  const findBlocks = () => wrapper.findAllComponents(SnippetCodeBlock);
  const findSnippets = () => findBlocks().wrappers.map((b) => b.props('snippet'));

  const findStepTexts = () =>
    findSteps().wrappers.map((s) => s.findAll('p').wrappers.map((p) => p.text()));

  const createComponent = ({ format = 'MAVEN', kind, provide = {} } = {}) => {
    wrapper = mountExtended(ArtifactsEmptyState, {
      propsData: { name: 'my-repository', format, kind },
      provide: { slug: SLUG, clientBaseUrl: CLIENT_BASE_URL, ...provide },
    });
  };

  describe('the heading and support text', () => {
    it.each([
      ['MAVEN', 'packages', 'package'],
      ['NPM', 'packages', 'package'],
      ['DOCKER', 'images', 'image'],
      ['OCI', 'images', 'image'],
    ])('names what a %s repository holds', (format, plural, singular) => {
      createComponent({ format });

      expect(findEmptyState().props('title')).toBe(`There are no ${plural} in this repository yet`);
      expect(findEmptyState().props('description')).toBe(
        `Publish your first ${singular} to get started.`,
      );
    });

    it('renders the illustration', () => {
      createComponent();

      expect(findEmptyState().props('svgPath')).toContain('empty-package');
    });

    it('links only to the glab command reference, which the first step names', () => {
      createComponent();

      expect(wrapper.findAll('a').wrappers.map((a) => a.attributes('href'))).toEqual([
        'https://docs.gitlab.com/cli/artifact-registry/login/',
      ]);
    });
  });

  describe('the setup steps', () => {
    beforeEach(() => createComponent());

    it('renders one numbered list under a single heading', () => {
      expect(findSetup().find('ol').exists()).toBe(true);
      expect(
        findSetup()
          .findAll('h3')
          .wrappers.map((h) => h.text()),
      ).toEqual(['CLI commands']);
    });

    it('sets the repository up first and publishes last, the order the steps are performed in', () => {
      expect(findSteps().wrappers.map((s) => s.findAll('p').wrappers.map((p) => p.text()))).toEqual(
        [
          [
            'glab reads your GitLab token from GITLAB_TOKEN. If that is not set, run glab auth login first.',
            'Run the following command with glab 1.115 or later:',
            'The token lasts 15 minutes by default, and up to 12 hours if you request a longer duration. Run the command again before it expires.',
          ],
          ["If you haven't already, add the configuration below to your pom.xml file:"],
          ['Add this to your pom.xml file:'],
          ['Publish command:'],
        ],
      );
    });

    it('puts the GITLAB_TOKEN note in the yarn step that runs glab', async () => {
      createComponent({ format: 'NPM' });

      findSelector().vm.$emit('select', 'yarn');
      await nextTick();

      expect(findSteps().wrappers.map((s) => s.findAll('p').wrappers.map((p) => p.text()))).toEqual(
        [
          ['Yarn 2.0 and later read registry settings from .yarnrc.yml. Add this to that file:'],
          [
            'glab reads your GitLab token from GITLAB_TOKEN. If that is not set, run glab auth login first.',
            'Run the following command with glab 1.115 or later:',
            'The token lasts 15 minutes by default, and up to 12 hours if you request a longer duration. Run the command again before it expires.',
          ],
          ['Publish command:'],
        ],
      );
    });

    it('keeps every snippet inside the step it belongs to', () => {
      findSteps().wrappers.forEach((step) => {
        expect(step.findAllComponents(SnippetCodeBlock)).toHaveLength(1);
      });
    });

    it('renders the publish snippets', () => {
      expect(findSnippets()).toContain('mvn deploy');
    });

    it.each([
      ['MAVEN', 4],
      ['NPM', 3],
      ['DOCKER', 2],
      ['OCI', 2],
    ])('gives a %s repository the steps its format needs', (format, steps) => {
      createComponent({ format });

      expect(findSteps()).toHaveLength(steps);
    });
  });

  describe('the snippets', () => {
    it('composes them from this repository’s own client URL', () => {
      createComponent();

      expect(findSnippets().join('\n')).toContain(
        'https://artifact-registry.example.com/acme/maven/my-repository',
      );
    });

    it.each(['MAVEN', 'NPM', 'DOCKER', 'OCI'])(
      'authenticates a %s repository through glab, so no step asks for a token by hand',
      (format) => {
        createComponent({ format });
        const snippets = findSnippets().join('\n');

        expect(snippets).toContain('glab artifact-registry login');
        expect(snippets).not.toContain('ARTIFACT_REGISTRY_TOKEN');
      },
    );

    it('leaves the hand-written alternative to the setup drawer', () => {
      createComponent({ format: 'DOCKER' });

      expect(findSnippets().join('\n')).not.toContain('docker login');
    });

    it('names what each copy button copies', () => {
      createComponent({ format: 'DOCKER' });

      expect(findBlocks().wrappers.map((b) => b.props('copyText'))).toEqual([
        'Copy the glab login command',
        'Copy the push command',
      ]);
    });
  });

  describe('the tool selector', () => {
    it.each([
      ['MAVEN', 'maven'],
      ['NPM', 'npm'],
      ['DOCKER', 'docker'],
      ['OCI', 'docker'],
    ])('starts a %s repository on its first tool', (format, tool) => {
      createComponent({ format });

      expect(findSelector().props()).toMatchObject({ format, selected: tool });
    });

    it('swaps the steps when another tool is chosen', async () => {
      createComponent({ format: 'NPM' });

      expect(findSnippets()).toContain('npm publish');

      findSelector().vm.$emit('select', 'pnpm');
      await nextTick();

      expect(findSnippets()).toContain('pnpm publish');
    });

    it('falls back rather than keeping a tool the new format cannot offer', async () => {
      createComponent({ format: 'DOCKER' });

      findSelector().vm.$emit('select', 'podman');
      await nextTick();
      await wrapper.setProps({ format: 'MAVEN' });

      expect(findSelector().props('selected')).toBe('maven');
    });
  });

  describe('when the instance configures no Artifact Registry origin', () => {
    beforeEach(() => createComponent({ provide: { clientBaseUrl: '' } }));

    it('still shows the empty state', () => {
      expect(findEmptyState().props('title')).toBe('There are no packages in this repository yet');
    });

    it('renders no setup steps', () => {
      expect(findSetup().exists()).toBe(false);
      expect(findSteps()).toHaveLength(0);
    });
  });

  describe('for a remote repository', () => {
    it.each([
      ['MAVEN', 'packages', 'Packages'],
      ['NPM', 'packages', 'Packages'],
      ['DOCKER', 'images', 'Images'],
      ['OCI', 'images', 'Images'],
    ])('tells a %s repository to configure a client to pull', (format, plural, capitalized) => {
      createComponent({ format, kind: REPOSITORY_KIND_REMOTE });

      expect(findEmptyState().props('title')).toBe(
        `There are no ${plural} cached in this repository yet`,
      );
      expect(findEmptyState().props('description')).toBe(
        `Configure your client to use this remote repository. ${capitalized} will appear here as you pull them.`,
      );
    });

    it('sets Maven up to resolve through the repository, with no publish step', () => {
      createComponent({ kind: REPOSITORY_KIND_REMOTE });

      expect(findStepTexts()).toEqual([
        [
          'glab reads your GitLab token from GITLAB_TOKEN. If that is not set, run glab auth login first.',
          'Run the following command with glab 1.115 or later:',
          'The token lasts 15 minutes by default, and up to 12 hours if you request a longer duration. Run the command again before it expires.',
        ],
        ['To replace Maven Central, merge this configuration into your ~/.m2/settings.xml file:'],
        [
          'To also resolve snapshot dependencies, merge this configuration into your pom.xml file:',
          'Dependencies your build would fetch from Maven Central now resolve through this repository.',
        ],
      ]);
      expect(findSnippets()).not.toContain('mvn deploy');
    });

    it('sets npm up as the default registry', () => {
      createComponent({ format: 'NPM', kind: REPOSITORY_KIND_REMOTE });

      expect(findSnippets()).toContain(
        'registry=https://artifact-registry.example.com/acme/npm/my-repository/',
      );
      expect(findSnippets()).not.toContain('npm publish');
    });

    it.each(['DOCKER', 'OCI'])('logs in first and pulls last for a %s repository', (format) => {
      createComponent({ format, kind: REPOSITORY_KIND_REMOTE });

      expect(findBlocks().wrappers.map((b) => b.props('copyText'))).toEqual([
        'Copy the glab login command',
        'Copy the pull command',
      ]);
    });
  });
});
