import { escape } from 'lodash-es';
import { DOCS_URL } from '~/constants';
import { s__ } from '~/locale';
import { withoutScheme } from '../../../utils';
import {
  REPOSITORY_FORMAT_DOCKER,
  REPOSITORY_FORMAT_MAVEN,
  REPOSITORY_FORMAT_NPM,
  REPOSITORY_FORMAT_OCI,
  REPOSITORY_KIND_HOSTED,
  SETUP_SECTION_INSTALL,
  SETUP_TOOL_GRADLE_GROOVY,
  SETUP_TOOL_GRADLE_KOTLIN,
  SETUP_TOOL_ORAS,
  SETUP_TOOL_PNPM,
  SETUP_TOOL_PODMAN,
  SETUP_TOOL_SBT,
  SETUP_TOOL_YARN,
} from '../../../constants';

const PLACEHOLDER_GROUP_ID = 'com.company';
const PLACEHOLDER_ARTIFACT_ID = 'app';
const PLACEHOLDER_VERSION = '1.0.0';
const PLACEHOLDER_SCOPE = 'scope';
const PLACEHOLDER_PACKAGE = '@scope/package';
const PLACEHOLDER_IMAGE_NAME = 'image';
const PLACEHOLDER_TAG = 'tag';
const PLACEHOLDER_FILE = 'artifact.txt';

const YARN_BERRY_PUBLISH_VIA_NPM_PLUGIN = 'yarn npm publish';

const GLAB_LOGIN_DOCS_URL = `${DOCS_URL}/cli/artifact-registry/login/`;
const GLAB_GET_TOKEN_DOCS_URL = `${DOCS_URL}/cli/artifact-registry/get-token/`;

// ASCII alphanumerics plus the seven characters Maven, npm, semver, and OCI coordinates use. A
// Maven version range also needs '[](),', but a range is a constraint, not a published version.
const SAFE_COORDINATE = /^[A-Za-z0-9._~@/+-]+$/;

// Separate from SAFE_COORDINATE: adding a colon there would widen every coordinate's guard.
const CANONICAL_DIGEST = /^sha256:[a-f0-9]{64}$/;

const i18n = {
  repositorySetup: s__('ArtifactRegistry|Repository setup'),
  registrySetup: s__('ArtifactRegistry|Registry setup'),
  copyDependency: s__('ArtifactRegistry|Copy the dependency declaration'),
  copyInstallCommand: s__('ArtifactRegistry|Copy the install command'),
  copyPublishCommand: s__('ArtifactRegistry|Copy the publish command'),
  copyDistribution: s__('ArtifactRegistry|Copy the distribution management configuration'),
  copyRepositoryConfig: s__('ArtifactRegistry|Copy the repository configuration'),
  copySnapshotRepositoryConfig: s__('ArtifactRegistry|Copy the snapshot repository configuration'),
  copyRegistryConfig: s__('ArtifactRegistry|Copy the registry configuration'),
  copyPullCommand: s__('ArtifactRegistry|Copy the pull command'),
  copyPullByTagCommand: s__('ArtifactRegistry|Copy the pull-by-tag command'),
  copyPullByDigestCommand: s__('ArtifactRegistry|Copy the pull-by-digest command'),
  copyPushCommand: s__('ArtifactRegistry|Copy the push command'),
  copyGlabCommand: s__('ArtifactRegistry|Copy the glab login command'),
  copyRegistryPointer: s__('ArtifactRegistry|Copy the registry line'),
  installCommand: s__('ArtifactRegistry|Install command:'),
  publishCommand: s__('ArtifactRegistry|Publish command:'),
  mavenDependency: s__(
    'ArtifactRegistry|Copy and paste this inside your %{codeStart}pom.xml%{codeEnd} %{codeStart}dependencies%{codeEnd} block:',
  ),
  mavenDistribution: s__('ArtifactRegistry|Add this to your %{codeStart}pom.xml%{codeEnd} file:'),
  mavenRepository: s__(
    "ArtifactRegistry|If you haven't already, add the configuration below to your %{codeStart}pom.xml%{codeEnd} file:",
  ),
  gradleGroovyDependency: s__(
    'ArtifactRegistry|Add the dependency to your %{codeStart}build.gradle%{codeEnd} file:',
  ),
  gradleGroovyRepository: s__(
    'ArtifactRegistry|Add the repository to your %{codeStart}build.gradle%{codeEnd} file, using the values glab wrote to %{codeStart}gradle.properties%{codeEnd}:',
  ),
  gradleKotlinRepository: s__(
    'ArtifactRegistry|Add the repository to your %{codeStart}build.gradle.kts%{codeEnd} file, using the values glab wrote to %{codeStart}gradle.properties%{codeEnd}:',
  ),
  gradleKotlinDependency: s__(
    'ArtifactRegistry|Add the dependency to your %{codeStart}build.gradle.kts%{codeEnd} file:',
  ),
  sbtDependency: s__(
    'ArtifactRegistry|Add the dependency to your %{codeStart}build.sbt%{codeEnd} file:',
  ),
  sbtRepository: s__('ArtifactRegistry|Add this to your %{codeStart}build.sbt%{codeEnd} file:'),
  mavenMirror: s__(
    'ArtifactRegistry|To replace Maven Central, merge this configuration into your %{codeStart}~/.m2/settings.xml%{codeEnd} file:',
  ),
  mavenSnapshots: s__(
    'ArtifactRegistry|To also resolve snapshot dependencies, merge this configuration into your %{codeStart}pom.xml%{codeEnd} file:',
  ),
  gradleGroovyDefaultRepository: s__(
    'ArtifactRegistry|Add the repository to your %{codeStart}build.gradle%{codeEnd} file in place of %{codeStart}mavenCentral()%{codeEnd}, using the values glab wrote to %{codeStart}gradle.properties%{codeEnd}:',
  ),
  gradleKotlinDefaultRepository: s__(
    'ArtifactRegistry|Add the repository to your %{codeStart}build.gradle.kts%{codeEnd} file in place of %{codeStart}mavenCentral()%{codeEnd}, using the values glab wrote to %{codeStart}gradle.properties%{codeEnd}:',
  ),
  sbtDefaultResolver: s__(
    'ArtifactRegistry|To use this repository in place of Maven Central, add this to your %{codeStart}build.sbt%{codeEnd} file:',
  ),
  npmrcRegistry: s__(
    'ArtifactRegistry|Add the registry to your %{codeStart}~/.npmrc%{codeEnd} file:',
  ),
  npmrcDefaultRegistry: s__(
    'ArtifactRegistry|Set this repository as your default registry in your %{codeStart}~/.npmrc%{codeEnd} file:',
  ),
  yarnrc: s__(
    'ArtifactRegistry|Yarn 2.0 and later read registry settings from %{codeStart}.yarnrc.yml%{codeEnd}. Add this to that file:',
  ),
  yarnrcDefaultRegistry: s__(
    'ArtifactRegistry|Yarn 2.0 and later read registry settings from %{codeStart}.yarnrc.yml%{codeEnd}. To set this repository as your default registry, add this to that file:',
  ),
  resolvesMavenCentralThroughRepository: s__(
    'ArtifactRegistry|Dependencies your build would fetch from Maven Central now resolve through this repository.',
  ),
  resolvesThroughRepository: s__(
    'ArtifactRegistry|Packages that use the default registry now resolve through this repository. Scope-specific registry settings still apply.',
  ),
  dockerHubImageName: s__(
    'ArtifactRegistry|For images from Docker Hub, use the full image name. Official images need the %{codeStart}library/%{codeEnd} prefix, for example %{codeStart}library/alpine%{codeEnd}.',
  ),
  pullImage: s__('ArtifactRegistry|Pull an image:'),
  pullByTag: s__('ArtifactRegistry|Pull by tag'),
  pullByDigest: s__('ArtifactRegistry|Pull by digest'),
  pushImage: s__('ArtifactRegistry|Push an image:'),
  glabLogin: s__(
    'ArtifactRegistry|Run the following command with %{linkStart}glab%{linkEnd} 1.115 or later:',
  ),
  glabToken: s__(
    'ArtifactRegistry|glab reads your GitLab token from %{codeStart}GITLAB_TOKEN%{codeEnd}. If that is not set, run %{codeStart}glab auth login%{codeEnd} first.',
  ),
  glabDockerCredential: s__(
    'ArtifactRegistry|The Docker credential helper ignores %{codeStart}GITLAB_TOKEN%{codeEnd}. If glab has no stored credential, run %{codeStart}glab auth login%{codeEnd} first.',
  ),
  tokenExpiry: s__(
    'ArtifactRegistry|The token lasts 15 minutes by default, and up to 12 hours if you request a longer duration. Run the command again before it expires.',
  ),
  tokenNotRefreshed: s__(
    'ArtifactRegistry|You cannot refresh this token. Run the command again before it expires.',
  ),
};

const hostOf = (url) => new URL(url).host;

/* eslint-disable @gitlab/require-i18n-strings -- Snippet bodies are code, not interface copy. */

// The '.' is load-bearing: a slug cannot contain one, so no two repositories share an alias.
const aliasPart = (value) =>
  String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-');

export const glabRegistryAlias = ({ slug, name }) => `ar-${aliasPart(slug)}.${aliasPart(name)}`;

const glabLoginBlocks = ({ flag, registry, alias }) => {
  const docker = flag === 'docker';

  return [
    { text: docker ? i18n.glabDockerCredential : i18n.glabToken },
    {
      text: i18n.glabLogin,
      link: GLAB_LOGIN_DOCS_URL,
      code: [
        'glab artifact-registry login',
        `--${flag}`,
        `--registry ${registry}`,
        ...(alias ? [`--registry-alias ${alias}`] : []),
      ].join(' \\\n  '),
      copyText: i18n.copyGlabCommand,
    },
    ...(docker ? [] : [{ text: i18n.tokenExpiry }]),
  ];
};

const gradleSections = ({
  tool,
  section,
  defaultRegistry,
  slug,
  name,
  repositoryUrl,
  groupId = PLACEHOLDER_GROUP_ID,
  artifactId = PLACEHOLDER_ARTIFACT_ID,
  version = PLACEHOLDER_VERSION,
}) => {
  const kotlin = tool === SETUP_TOOL_GRADLE_KOTLIN;
  const coordinates = `${groupId}:${artifactId}:${version}`;
  const alias = glabRegistryAlias({ slug, name });
  const [defaultRepositoryText, additionalRepositoryText] = kotlin
    ? [i18n.gradleKotlinDefaultRepository, i18n.gradleKotlinRepository]
    : [i18n.gradleGroovyDefaultRepository, i18n.gradleGroovyRepository];
  const repositoryText = defaultRegistry ? defaultRepositoryText : additionalRepositoryText;

  return [
    {
      blocks: [
        section === SETUP_SECTION_INSTALL
          ? {
              text: kotlin ? i18n.gradleKotlinDependency : i18n.gradleGroovyDependency,
              code: kotlin ? `implementation("${coordinates}")` : `implementation '${coordinates}'`,
              copyText: i18n.copyDependency,
            }
          : {
              text: i18n.publishCommand,
              code: 'gradle publish',
              copyText: i18n.copyPublishCommand,
            },
      ],
    },
    {
      heading: i18n.repositorySetup,
      blocks: [
        ...glabLoginBlocks({ flag: 'gradle', registry: repositoryUrl, alias }),
        {
          text: repositoryText,
          code: kotlin
            ? `maven {
  url = uri(providers.gradleProperty("${alias}Url").get())
  credentials {
    username = providers.gradleProperty("${alias}Username").get()
    password = providers.gradleProperty("${alias}Password").get()
  }
}`
            : `maven {
  url providers.gradleProperty('${alias}Url').get()
  credentials {
    username = providers.gradleProperty('${alias}Username').get()
    password = providers.gradleProperty('${alias}Password').get()
  }
}`,
          copyText: i18n.copyRepositoryConfig,
        },
      ],
    },
  ];
};

const sbtRepositoryConfig = ({ section, defaultRegistry, repositoryUrl }) => {
  if (section !== SETUP_SECTION_INSTALL) {
    return {
      text: i18n.sbtRepository,
      code: `publishTo := Some("artifact-registry" at "${repositoryUrl}")`,
    };
  }

  if (defaultRegistry) {
    return {
      text: i18n.sbtDefaultResolver,
      code: `externalResolvers := Resolver.combineDefaultResolvers(resolvers.value.toVector :+ ("artifact-registry" at "${repositoryUrl}"), mavenCentral = false)`,
    };
  }

  return {
    text: i18n.sbtRepository,
    code: `resolvers += ("artifact-registry" at "${repositoryUrl}")`,
  };
};

const mavenSections = ({
  tool,
  section,
  defaultRegistry,
  slug,
  name,
  repositoryUrl,
  groupId = PLACEHOLDER_GROUP_ID,
  artifactId = PLACEHOLDER_ARTIFACT_ID,
  version = PLACEHOLDER_VERSION,
}) => {
  if (tool === SETUP_TOOL_GRADLE_GROOVY || tool === SETUP_TOOL_GRADLE_KOTLIN) {
    return gradleSections({
      tool,
      section,
      defaultRegistry,
      slug,
      name,
      repositoryUrl,
      groupId,
      artifactId,
      version,
    });
  }

  if (tool === SETUP_TOOL_SBT) {
    return [
      {
        blocks: [
          section === SETUP_SECTION_INSTALL
            ? {
                text: i18n.sbtDependency,
                code: `libraryDependencies += "${groupId}" % "${artifactId}" % "${version}"`,
                copyText: i18n.copyDependency,
              }
            : { text: i18n.publishCommand, code: 'sbt publish', copyText: i18n.copyPublishCommand },
        ],
      },
      {
        heading: i18n.repositorySetup,
        blocks: [
          ...glabLoginBlocks({ flag: 'sbt', registry: repositoryUrl }),
          {
            ...sbtRepositoryConfig({ section, defaultRegistry, repositoryUrl }),
            copyText: i18n.copyRepositoryConfig,
          },
        ],
      },
    ];
  }

  // The reader pastes these blocks into their own pom.xml and settings.xml, so a
  // repository name carrying an XML metacharacter would inject elements into a build
  // file rather than break a page. Artifact Registry restricts the name charset today
  // (REPOSITORY_NAME_PATTERN), which this does not take on trust.
  const xmlAlias = escape(glabRegistryAlias({ slug, name }));
  const xmlUrl = escape(repositoryUrl);

  return [
    {
      blocks:
        section === SETUP_SECTION_INSTALL
          ? [
              {
                text: i18n.mavenDependency,
                // groupId, artifactId, and version already passed SAFE_COORDINATE, so these
                // escapes are unreachable; kept so all five interpolations escape the same way.
                code: `<dependency>
  <groupId>${escape(groupId)}</groupId>
  <artifactId>${escape(artifactId)}</artifactId>
  <version>${escape(version)}</version>
</dependency>`,
                copyText: i18n.copyDependency,
              },
              {
                text: i18n.installCommand,
                code: 'mvn install',
                copyText: i18n.copyInstallCommand,
              },
            ]
          : [
              {
                text: i18n.mavenDistribution,
                code: `<distributionManagement>
  <repository>
    <id>${xmlAlias}</id>
    <url>${xmlUrl}</url>
  </repository>
</distributionManagement>`,
                copyText: i18n.copyDistribution,
              },
              {
                text: i18n.publishCommand,
                code: 'mvn deploy',
                copyText: i18n.copyPublishCommand,
              },
            ],
    },
    {
      heading: i18n.repositorySetup,
      blocks: [
        ...glabLoginBlocks({ flag: 'maven', registry: repositoryUrl, alias: xmlAlias }),
        defaultRegistry
          ? {
              text: i18n.mavenMirror,
              code: `<mirrors>
  <mirror>
    <id>${xmlAlias}</id>
    <url>${xmlUrl}</url>
    <mirrorOf>central</mirrorOf>
  </mirror>
</mirrors>`,
              copyText: i18n.copyRepositoryConfig,
            }
          : {
              text: i18n.mavenRepository,
              code: `<repositories>
  <repository>
    <id>${xmlAlias}</id>
    <url>${xmlUrl}</url>
  </repository>
</repositories>`,
              copyText: i18n.copyRepositoryConfig,
            },
        ...(defaultRegistry
          ? [
              {
                text: i18n.mavenSnapshots,
                code: `<repositories>
  <repository>
    <id>${xmlAlias}</id>
    <url>${xmlUrl}</url>
    <snapshots>
      <enabled>true</enabled>
    </snapshots>
  </repository>
</repositories>`,
                copyText: i18n.copySnapshotRepositoryConfig,
              },
            ]
          : []),
      ],
    },
  ];
};

const npmSections = ({
  tool,
  section,
  defaultRegistry,
  repositoryUrl,
  packageName = PLACEHOLDER_PACKAGE,
  version,
}) => {
  const client = { [SETUP_TOOL_YARN]: 'yarn', [SETUP_TOOL_PNPM]: 'pnpm' }[tool] ?? 'npm';
  const registryUrl = `${repositoryUrl}/`;
  const addCommand = client === 'npm' ? 'install' : 'add';
  // `version` takes no placeholder default: the setup drawer passes none, and pinning one there
  // would change the merged snippet it already renders.
  const installTarget = version ? `${packageName}@${version}` : packageName;
  const publishCommand =
    client === 'yarn' ? YARN_BERRY_PUBLISH_VIA_NPM_PLUGIN : `${client} publish`;

  return [
    {
      blocks: [
        section === SETUP_SECTION_INSTALL
          ? {
              text: i18n.installCommand,
              code: `${client} ${addCommand} ${installTarget}`,
              copyText: i18n.copyInstallCommand,
            }
          : {
              text: i18n.publishCommand,
              code: publishCommand,
              copyText: i18n.copyPublishCommand,
            },
      ],
    },
    {
      heading: i18n.registrySetup,
      blocks:
        tool === SETUP_TOOL_YARN
          ? [
              defaultRegistry
                ? {
                    text: i18n.yarnrcDefaultRegistry,
                    code: `npmRegistryServer: "${registryUrl}"
npmRegistries:
  "${registryUrl}":
    npmAlwaysAuth: true
    npmAuthToken: "\${ARTIFACT_REGISTRY_TOKEN:-}"`,
                    copyText: i18n.copyRegistryConfig,
                  }
                : {
                    text: i18n.yarnrc,
                    code: `npmScopes:
  ${PLACEHOLDER_SCOPE}:
    npmRegistryServer: "${registryUrl}"
    npmAuthToken: "\${ARTIFACT_REGISTRY_TOKEN:-}"`,
                    copyText: i18n.copyRegistryConfig,
                  },
              { text: i18n.glabToken, startsStep: true },
              {
                text: i18n.glabLogin,
                link: GLAB_GET_TOKEN_DOCS_URL,
                code: 'export ARTIFACT_REGISTRY_TOKEN="$(glab artifact-registry get-token)"',
                copyText: i18n.copyGlabCommand,
              },
              { text: i18n.tokenExpiry },
            ]
          : [
              ...glabLoginBlocks({ flag: 'npm', registry: registryUrl }),
              defaultRegistry
                ? {
                    text: i18n.npmrcDefaultRegistry,
                    code: `registry=${registryUrl}`,
                    copyText: i18n.copyRegistryPointer,
                  }
                : {
                    text: i18n.npmrcRegistry,
                    code: `@${PLACEHOLDER_SCOPE}:registry=${registryUrl}`,
                    copyText: i18n.copyRegistryPointer,
                  },
            ],
    },
  ];
};

const containerSections = ({
  tool,
  section,
  defaultRegistry,
  format,
  repositoryUrl,
  imageName = PLACEHOLDER_IMAGE_NAME,
  tag,
  digest,
}) => {
  const client = { [SETUP_TOOL_PODMAN]: 'podman', [SETUP_TOOL_ORAS]: 'oras' }[tool] ?? 'docker';
  const image = `${withoutScheme(repositoryUrl)}/${imageName}`;
  const host = hostOf(repositoryUrl);

  const registrySetup = {
    heading: i18n.registrySetup,
    blocks:
      tool === SETUP_TOOL_PODMAN
        ? [
            { text: i18n.glabToken },
            {
              text: i18n.glabLogin,
              link: GLAB_GET_TOKEN_DOCS_URL,
              code: `glab artifact-registry get-token |
  podman login ${host} --username __token__ --password-stdin`,
              copyText: i18n.copyGlabCommand,
            },
            { text: i18n.tokenNotRefreshed },
          ]
        : glabLoginBlocks({ flag: 'docker', registry: host }),
  };

  // Install only: a push addresses a tag, never a digest.
  if (digest && section === SETUP_SECTION_INSTALL) {
    // Scoped to this arm on purpose: hoisting it onto `client` would reach the setup drawer,
    // which addresses a tag, and switch every OCI repository there to oras.
    const digestClient = format === REPOSITORY_FORMAT_OCI ? 'oras' : client;

    return [
      {
        blocks: [
          ...(tag
            ? [
                {
                  text: i18n.pullByTag,
                  code: `${digestClient} pull ${image}:${tag}`,
                  copyText: i18n.copyPullByTagCommand,
                },
              ]
            : []),
          {
            text: i18n.pullByDigest,
            code: `${digestClient} pull ${image}@${digest}`,
            copyText: i18n.copyPullByDigestCommand,
          },
        ],
      },
      registrySetup,
    ];
  }

  // Defaulting `tag` in the destructure instead would make an untagged manifest pull `image:tag`.
  const reference = `${image}:${tag ?? PLACEHOLDER_TAG}`;

  return [
    {
      blocks:
        section === SETUP_SECTION_INSTALL
          ? [
              {
                text: i18n.pullImage,
                code: `${client} pull ${reference}`,
                copyText: i18n.copyPullCommand,
              },
              ...(defaultRegistry ? [{ text: i18n.dockerHubImageName }] : []),
            ]
          : [
              {
                text: i18n.pushImage,
                code:
                  client === 'oras'
                    ? `oras push ${reference} ${PLACEHOLDER_FILE}`
                    : `${client} push ${reference}`,
                copyText: i18n.copyPushCommand,
              },
            ],
    },
    registrySetup,
  ];
};

/* eslint-enable @gitlab/require-i18n-strings */

const PACKAGE_FORMATS = [REPOSITORY_FORMAT_MAVEN, REPOSITORY_FORMAT_NPM];

const SECTION_BUILDERS = {
  [REPOSITORY_FORMAT_DOCKER]: containerSections,
  [REPOSITORY_FORMAT_OCI]: containerSections,
  [REPOSITORY_FORMAT_MAVEN]: mavenSections,
  [REPOSITORY_FORMAT_NPM]: npmSections,
};

export const setupSnippetSections = ({
  format,
  kind,
  tool,
  section,
  slug,
  name,
  repositoryUrl,
  groupId,
  artifactId,
  packageName,
  version,
  imageName,
  tag,
  digest,
}) => {
  const build = SECTION_BUILDERS[format];

  if (!build || !repositoryUrl || !name) return [];

  // Absent, not refused: an untagged manifest arrives as `tag: null`, and refusing it would
  // empty the whole panel. The identity coordinates below are deliberately not treated this way.
  const givenTag = tag || undefined;
  const givenDigest = digest || undefined;

  // Only undefined reaches a builder's placeholder default, and GraphQL sends null for an unset
  // field, so a non-string has to be refused rather than coerced into the charset test.
  const isSafe = (coordinate) =>
    coordinate === undefined ||
    (typeof coordinate === 'string' && SAFE_COORDINATE.test(coordinate));

  const isSafeDigest = (value) =>
    value === undefined || (typeof value === 'string' && CANONICAL_DIGEST.test(value));

  if (![groupId, artifactId, packageName, version, imageName, givenTag].every(isSafe)) return [];
  if (!isSafeDigest(givenDigest)) return [];

  const defaultRegistry = Boolean(kind) && kind !== REPOSITORY_KIND_HOSTED;
  const sections = build({
    tool,
    section,
    defaultRegistry,
    format,
    slug,
    name,
    repositoryUrl,
    groupId,
    artifactId,
    packageName,
    version,
    imageName,
    tag: givenTag,
    digest: givenDigest,
  });

  if (!defaultRegistry || section !== SETUP_SECTION_INSTALL || !PACKAGE_FORMATS.includes(format)) {
    return sections;
  }

  const setup = sections.at(-1);

  if (format === REPOSITORY_FORMAT_NPM && tool === SETUP_TOOL_YARN) {
    return [setup];
  }

  const text =
    format === REPOSITORY_FORMAT_MAVEN
      ? i18n.resolvesMavenCentralThroughRepository
      : i18n.resolvesThroughRepository;

  return [{ ...setup, blocks: [...setup.blocks, { text }] }];
};

// Force HOSTED so blocks[0] stays the install command. Remote and virtual
// npm and Maven output drops the install section.
export const installSnippetBlock = (args) =>
  setupSnippetSections({ ...args, kind: REPOSITORY_KIND_HOSTED, section: SETUP_SECTION_INSTALL })[0]
    ?.blocks?.[0] ?? null;
