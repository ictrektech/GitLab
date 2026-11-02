import {
  REPOSITORY_FORMAT_VALUES,
  SETUP_SECTION_INSTALL,
  SETUP_SECTION_PUBLISH,
  SETUP_TOOLS,
} from 'ee/packages_and_registries/artifact_registry/constants';
import {
  installSnippetBlock,
  setupSnippetSections,
} from 'ee/packages_and_registries/artifact_registry/repositories/detail/setup_instructions/snippets';
import { buildRepositoryClientUrl } from 'ee/packages_and_registries/artifact_registry/utils';
import { CLIENT_BASE_URL, SLUG } from '../../../mock_data';

const NAME = 'my-repository';
const ALIAS = 'ar-acme.my-repository';
const SECTIONS = [SETUP_SECTION_INSTALL, SETUP_SECTION_PUBLISH];
const DIGEST = `sha256:${'a1b2c3d4'.repeat(8)}`;

const urlFor = (format) =>
  buildRepositoryClientUrl({ clientBaseUrl: CLIENT_BASE_URL, slug: SLUG, format, name: NAME });

const build = ({ format, kind, tool, section }) =>
  setupSnippetSections({
    format,
    kind,
    tool,
    section,
    slug: SLUG,
    name: NAME,
    repositoryUrl: urlFor(format),
  });

const codeOf = (sections) =>
  sections.flatMap(({ blocks }) => blocks.map(({ code }) => code).filter(Boolean));

const textOf = (sections) => sections.flatMap(({ blocks }) => blocks.map(({ text }) => text));

const everyCombination = REPOSITORY_FORMAT_VALUES.flatMap((format) =>
  SETUP_TOOLS[format].flatMap(({ value: tool }) => [
    ...['HOSTED', 'VIRTUAL', 'REMOTE'].map((kind) => ({
      format,
      tool,
      section: SETUP_SECTION_INSTALL,
      kind,
    })),
    { format, tool, section: SETUP_SECTION_PUBLISH, kind: 'HOSTED' },
  ]),
);

describe('setupSnippetSections', () => {
  describe('what a format, tool, and section produce', () => {
    it.each(everyCombination)(
      'gives a $format repository on $tool a $section section with at least one command ($kind)',
      ({ format, tool, section, kind }) => {
        expect(codeOf(build({ format, kind, tool, section }))).not.toHaveLength(0);
      },
    );

    it.each(everyCombination)(
      'ends the $format / $tool / $section / $kind content with a setup section a client needs to reach the repository',
      ({ format, tool, section, kind }) => {
        const sections = build({ format, kind, tool, section });

        expect(sections.at(-1).heading).toEqual(expect.any(String));
      },
    );

    it('identifies the Maven repository by the same alias the glab command registers', () => {
      const sections = build({ format: 'MAVEN', tool: 'maven', section: SETUP_SECTION_PUBLISH });
      const body = codeOf(sections).join('\n');

      expect(body).toContain(`--registry-alias ${ALIAS}`);
      expect(body.match(/<id>[^<]*<\/id>/g)).toEqual([`<id>${ALIAS}</id>`, `<id>${ALIAS}</id>`]);
    });
  });

  describe('the repository URL every snippet is composed on', () => {
    it.each(everyCombination)(
      'addresses this repository, not a placeholder, for $format on $tool ($section, $kind)',
      ({ format, tool, section, kind }) => {
        const url = urlFor(format);
        const address = url;
        const withUrl = codeOf(build({ format, kind, tool, section })).filter(
          (code) => code.includes(address) || code.includes(address.replace('https://', '')),
        );

        expect(withUrl).not.toHaveLength(0);
      },
    );

    it('strips the scheme where a container reference cannot carry one', () => {
      const [pull] = codeOf(
        build({ format: 'DOCKER', tool: 'docker', section: SETUP_SECTION_INSTALL }),
      );

      expect(pull).toBe(
        'docker pull artifact-registry.example.com/acme/container/my-repository/image:tag',
      );
    });

    it.each`
      tool        | signIn
      ${'docker'} | ${'--registry artifact-registry.example.com:8443'}
      ${'podman'} | ${'podman login artifact-registry.example.com:8443 '}
    `(
      'keeps the registry port in the $tool sign-in command, which Docker matches on',
      ({ tool, signIn }) => {
        const glab = codeOf(
          setupSnippetSections({
            format: 'OCI',
            tool,
            section: SETUP_SECTION_INSTALL,
            slug: SLUG,
            name: NAME,
            repositoryUrl:
              'https://artifact-registry.example.com:8443/acme/container/my-repository',
          }),
        ).find((code) => code.startsWith('glab artifact-registry'));

        expect(glab).toContain(signIn);
      },
    );

    it('hands sbt the full registry URL, port included, which glab keys its entry on', () => {
      const url = 'https://artifact-registry.example.com:8443/acme/maven/my-repository';
      const glab = codeOf(
        setupSnippetSections({
          format: 'MAVEN',
          tool: 'sbt',
          section: SETUP_SECTION_INSTALL,
          slug: SLUG,
          name: NAME,
          repositoryUrl: url,
        }),
      ).find((code) => code.startsWith('glab artifact-registry login'));

      expect(glab).toContain(`--registry ${url}`);
    });
  });

  describe('switching the build tool', () => {
    it.each(REPOSITORY_FORMAT_VALUES)(
      'gives a %s repository different commands for each of its tools',
      (format) => {
        const perTool = SETUP_TOOLS[format].map(({ value: tool }) =>
          JSON.stringify(codeOf(build({ format, tool, section: SETUP_SECTION_PUBLISH }))),
        );

        expect(new Set(perTool).size).toBe(perTool.length);
      },
    );

    it('offers Gradle its own DSL rather than repeating the Maven command', () => {
      const groovy = codeOf(
        build({ format: 'MAVEN', tool: 'gradle_groovy', section: SETUP_SECTION_PUBLISH }),
      );
      const kotlin = codeOf(
        build({ format: 'MAVEN', tool: 'gradle_kotlin', section: SETUP_SECTION_PUBLISH }),
      );

      expect(groovy).toContain('gradle publish');
      expect(kotlin).toContain('gradle publish');
      expect(groovy.join()).not.toContain('mvn');
    });

    it.each([SETUP_SECTION_INSTALL, SETUP_SECTION_PUBLISH])(
      'varies only the DSL between the Gradle tools in %s, never the Gradle install',
      (section) => {
        const forTool = (tool) => codeOf(build({ format: 'MAVEN', tool, section }));

        expect(forTool('gradle_groovy').join()).not.toContain('./gradlew');
        expect(forTool('gradle_kotlin').join()).not.toContain('./gradlew');
      },
    );

    it('publishes yarn through the Berry npm plugin, not the Classic `yarn publish`', () => {
      const [publish, registry] = codeOf(
        build({ format: 'NPM', tool: 'yarn', section: SETUP_SECTION_PUBLISH }),
      );

      expect(publish).toBe('yarn npm publish');
      expect(registry).toContain('npmScopes:');
    });
  });

  describe('credentials', () => {
    it.each(everyCombination)(
      'carries no credential for $format on $tool ($section, $kind)',
      ({ format, tool, section, kind }) => {
        const body = codeOf(build({ format, kind, tool, section })).join('\n');

        expect(body).not.toMatch(/glpat-|--password[= ](?!-stdin)|-p\s+\S|Bearer\s/);
        expect(body.includes('ARTIFACT_REGISTRY_TOKEN')).toBe(
          body.includes('export ARTIFACT_REGISTRY_TOKEN="$(glab artifact-registry get-token)"'),
        );
      },
    );

    it.each(everyCombination)(
      'leaves authentication to glab for $format on $tool ($section, $kind)',
      ({ format, tool, section, kind }) => {
        const blocks = build({ format, kind, tool, section }).flatMap(({ blocks: b }) => b);
        const authenticates = blocks.some(({ code }) =>
          /glab artifact-registry (login|get-token)/.test(code),
        );

        expect(authenticates).toBe(true);
      },
    );

    it.each`
      kind         | section                  | text                                                                                                          | configuration
      ${'HOSTED'}  | ${SETUP_SECTION_INSTALL} | ${'Add this to your %{codeStart}build.sbt%{codeEnd} file:'}                                                   | ${'resolvers += ("artifact-registry" at "https://artifact-registry.example.com/acme/maven/my-repository")'}
      ${'HOSTED'}  | ${SETUP_SECTION_PUBLISH} | ${'Add this to your %{codeStart}build.sbt%{codeEnd} file:'}                                                   | ${'publishTo := Some("artifact-registry" at "https://artifact-registry.example.com/acme/maven/my-repository")'}
      ${'VIRTUAL'} | ${SETUP_SECTION_INSTALL} | ${'To use this repository in place of Maven Central, add this to your %{codeStart}build.sbt%{codeEnd} file:'} | ${'externalResolvers := Resolver.combineDefaultResolvers(resolvers.value.toVector :+ ("artifact-registry" at "https://artifact-registry.example.com/acme/maven/my-repository"), mavenCentral = false)'}
      ${'REMOTE'}  | ${SETUP_SECTION_INSTALL} | ${'To use this repository in place of Maven Central, add this to your %{codeStart}build.sbt%{codeEnd} file:'} | ${'externalResolvers := Resolver.combineDefaultResolvers(resolvers.value.toVector :+ ("artifact-registry" at "https://artifact-registry.example.com/acme/maven/my-repository"), mavenCentral = false)'}
      ${'VIRTUAL'} | ${SETUP_SECTION_PUBLISH} | ${'Add this to your %{codeStart}build.sbt%{codeEnd} file:'}                                                   | ${'publishTo := Some("artifact-registry" at "https://artifact-registry.example.com/acme/maven/my-repository")'}
    `(
      'configures the sbt repository for $section on a $kind repository',
      ({ kind, section, text, configuration }) => {
        const sections = build({ format: 'MAVEN', kind, tool: 'sbt', section });

        expect(sections.flatMap(({ blocks }) => blocks)).toContainEqual(
          expect.objectContaining({ text, code: configuration }),
        );
      },
    );

    it.each(['maven', 'gradle_groovy', 'gradle_kotlin'])(
      'does not configure unsupported HTTP header authentication for %s',
      (tool) => {
        const body = codeOf(build({ format: 'MAVEN', tool, section: SETUP_SECTION_INSTALL })).join(
          '\n',
        );

        expect(body).not.toContain('Private-Token');
        expect(body).not.toContain('HttpHeaderCredentials');
        expect(body).not.toContain('authentication {');
      },
    );
  });

  describe('a repository name carrying XML metacharacters', () => {
    const HOSTILE = 'a</id><url>https://evil.example/</url><id>b';

    const hostileSections = (section) =>
      setupSnippetSections({
        format: 'MAVEN',
        tool: 'maven',
        section,
        slug: SLUG,
        name: HOSTILE,
        repositoryUrl: urlFor('MAVEN'),
      });

    it.each(SECTIONS)('opens no new element anywhere in the %s XML', (section) => {
      const xml = codeOf(hostileSections(section)).filter((code) => code.startsWith('<'));

      expect(xml).not.toHaveLength(0);
      xml.forEach((code) => expect(code).not.toContain('<url>https://evil.example/</url>'));
    });

    const hostileXml = (section) =>
      codeOf(hostileSections(section)).filter((code) => code.startsWith('<'));

    it.each(SECTIONS)('confines the name to the alias charset where %s embeds it', (section) => {
      const withId = hostileXml(section).filter((code) => code.includes('<id>'));

      expect(withId).not.toHaveLength(0);
      withId.forEach((code) =>
        expect(code.match(/<id>([^<]*)<\/id>/)[1]).toMatch(/^[a-z0-9._-]+$/),
      );
    });

    it.each(SECTIONS)('keeps one id element per repository block in %s', (section) => {
      hostileXml(section)
        .filter((code) => code.includes('<id>'))
        .forEach((code) => {
          expect(code.match(/<id>/g)).toHaveLength(1);
        });
    });
  });

  describe('when no artifact coordinates are given', () => {
    it('leaves the Maven dependency on the module placeholders', () => {
      const [dependency] = codeOf(
        build({ format: 'MAVEN', tool: 'maven', section: SETUP_SECTION_INSTALL }),
      );

      expect(dependency).toBe(`<dependency>
  <groupId>com.company</groupId>
  <artifactId>app</artifactId>
  <version>1.0.0</version>
</dependency>`);
    });

    it.each(['gradle_groovy', 'gradle_kotlin'])(
      'leaves the %s dependency on the module placeholders',
      (tool) => {
        const [dependency] = codeOf(
          build({ format: 'MAVEN', tool, section: SETUP_SECTION_INSTALL }),
        );

        expect(dependency).toContain('com.company:app:1.0.0');
      },
    );

    it.each`
      tool      | command
      ${'npm'}  | ${'npm install @scope/package'}
      ${'yarn'} | ${'yarn add @scope/package'}
      ${'pnpm'} | ${'pnpm add @scope/package'}
    `('pins no version onto the $tool install command', ({ tool, command }) => {
      const [install] = codeOf(build({ format: 'NPM', tool, section: SETUP_SECTION_INSTALL }));

      expect(install).toBe(command);
    });
  });

  describe('when a version names its own coordinates', () => {
    const MAVEN_COORDINATES = {
      groupId: 'com.company.payment',
      artifactId: 'core',
      version: '2.4.1',
    };
    const NPM_COORDINATES = { packageName: '@company/design-system', version: '4.2.0' };

    const buildFor = ({ format, tool, coordinates }) =>
      setupSnippetSections({
        format,
        tool,
        section: SETUP_SECTION_INSTALL,
        slug: SLUG,
        name: NAME,
        repositoryUrl: urlFor(format),
        ...coordinates,
      });

    it('reads them back in the Maven dependency', () => {
      const [dependency] = codeOf(
        buildFor({ format: 'MAVEN', tool: 'maven', coordinates: MAVEN_COORDINATES }),
      );

      expect(dependency).toBe(`<dependency>
  <groupId>com.company.payment</groupId>
  <artifactId>core</artifactId>
  <version>2.4.1</version>
</dependency>`);
    });

    it.each`
      tool               | declaration
      ${'gradle_groovy'} | ${"implementation 'com.company.payment:core:2.4.1'"}
      ${'gradle_kotlin'} | ${'implementation("com.company.payment:core:2.4.1")'}
    `('reads them back in the $tool declaration', ({ tool, declaration }) => {
      const [dependency] = codeOf(
        buildFor({ format: 'MAVEN', tool, coordinates: MAVEN_COORDINATES }),
      );

      expect(dependency).toBe(declaration);
    });

    it.each`
      tool      | command
      ${'npm'}  | ${'npm install @company/design-system@4.2.0'}
      ${'yarn'} | ${'yarn add @company/design-system@4.2.0'}
      ${'pnpm'} | ${'pnpm add @company/design-system@4.2.0'}
    `('pins the version onto the $tool install command', ({ tool, command }) => {
      const [install] = codeOf(buildFor({ format: 'NPM', tool, coordinates: NPM_COORDINATES }));

      expect(install).toBe(command);
    });

    it('names the package without a version when the version is absent', () => {
      const [install] = codeOf(
        buildFor({
          format: 'NPM',
          tool: 'npm',
          coordinates: { packageName: '@company/design-system' },
        }),
      );

      expect(install).toBe('npm install @company/design-system');
    });

    it('leaves the publish section alone, which names the repository rather than an artifact', () => {
      const withCoordinates = setupSnippetSections({
        format: 'MAVEN',
        tool: 'maven',
        section: SETUP_SECTION_PUBLISH,
        slug: SLUG,
        name: NAME,
        repositoryUrl: urlFor('MAVEN'),
        ...MAVEN_COORDINATES,
      });

      expect(withCoordinates).toStrictEqual(
        build({ format: 'MAVEN', tool: 'maven', section: SETUP_SECTION_PUBLISH }),
      );
    });
  });

  describe('when a manifest names its own image and reference', () => {
    const IMAGE = { imageName: 'payment-service', tag: 'trixie', digest: DIGEST };

    const buildContainer = ({ format = 'DOCKER', tool = 'docker', ...rest } = {}) =>
      setupSnippetSections({
        format,
        tool,
        section: SETUP_SECTION_INSTALL,
        slug: SLUG,
        name: NAME,
        repositoryUrl: urlFor(format),
        ...rest,
      });

    const host = (format) => urlFor(format).replace(/^https?:\/\//, '');

    it.each`
      format      | client
      ${'DOCKER'} | ${'docker'}
      ${'OCI'}    | ${'oras'}
    `('pulls by tag and then by digest on $format, with $client', ({ format, client }) => {
      expect(codeOf(buildContainer({ format, ...IMAGE }))).toEqual([
        `${client} pull ${host(format)}/payment-service:trixie`,
        `${client} pull ${host(format)}/payment-service@${DIGEST}`,
        expect.stringContaining('glab artifact-registry login'),
      ]);
    });

    it.each(['docker', 'podman', 'oras'])(
      'pulls an OCI artifact with oras whatever %s is selected',
      (tool) => {
        expect(codeOf(buildContainer({ format: 'OCI', tool, ...IMAGE }))).toEqual([
          `oras pull ${host('OCI')}/payment-service:trixie`,
          `oras pull ${host('OCI')}/payment-service@${DIGEST}`,
          expect.stringMatching(/^glab artifact-registry /),
        ]);
      },
    );

    describe.each([SETUP_SECTION_INSTALL, SETUP_SECTION_PUBLISH])(
      'the digestless OCI command in the %s section',
      (section) => {
        it.each(['docker', 'podman', 'oras'])(
          'stays on the selected %s, which the drawer picks',
          (tool) => {
            expect(
              codeOf(
                buildContainer({ format: 'OCI', imageName: 'payment-service', section, tool }),
              ),
            ).toEqual([
              expect.stringMatching(new RegExp(`^${tool} (pull|push) `)),
              expect.stringMatching(/^glab artifact-registry /),
            ]);
          },
        );
      },
    );

    it('drops the by-tag command for an untagged manifest rather than pulling the placeholder', () => {
      const [pull] = buildContainer({ imageName: 'payment-service', digest: DIGEST });

      expect(pull.blocks).toHaveLength(1);
      expect(pull.blocks[0].code).toBe(`docker pull ${host('DOCKER')}/payment-service@${DIGEST}`);
    });

    it('labels the pair so a reader can tell the two references apart', () => {
      const [pull] = buildContainer(IMAGE);

      expect(pull.blocks.map(({ text }) => text)).toEqual(['Pull by tag', 'Pull by digest']);
    });

    it('names each copy button for the reference it copies, not just the pair', () => {
      const [pull] = buildContainer(IMAGE);

      expect(pull.blocks.map(({ copyText }) => copyText)).toEqual([
        'Copy the pull-by-tag command',
        'Copy the pull-by-digest command',
      ]);
    });

    it('carries the selected client through to both Docker commands', () => {
      expect(codeOf(buildContainer({ tool: 'podman', ...IMAGE }))).toEqual([
        `podman pull ${host('DOCKER')}/payment-service:trixie`,
        `podman pull ${host('DOCKER')}/payment-service@${DIGEST}`,
        expect.stringContaining('podman login'),
      ]);
    });

    it('keeps the single placeholder command when an image is named without a digest', () => {
      const [pull] = codeOf(buildContainer({ imageName: 'payment-service' }));

      expect(pull).toBe(`docker pull ${host('DOCKER')}/payment-service:tag`);
    });

    it('pushes by tag on the publish section, never by digest', () => {
      const [push] = codeOf(buildContainer({ ...IMAGE, section: SETUP_SECTION_PUBLISH }));

      expect(push).toBe(`docker push ${host('DOCKER')}/payment-service:trixie`);
    });

    describe.each([null, undefined, ''])('with a tag given as %p', (tag) => {
      it('drops the by-tag command and keeps the rest of the panel, glab command included', () => {
        expect(
          codeOf(buildContainer({ imageName: 'payment-service', tag, digest: DIGEST })),
        ).toEqual([
          `docker pull ${host('DOCKER')}/payment-service@${DIGEST}`,
          expect.stringContaining('glab artifact-registry login'),
        ]);
      });
    });

    describe.each([null, undefined, ''])('with a digest given as %p', (digest) => {
      it('falls back to the single by-tag command rather than emptying the panel', () => {
        expect(
          codeOf(buildContainer({ imageName: 'payment-service', tag: 'trixie', digest })),
        ).toEqual([
          `docker pull ${host('DOCKER')}/payment-service:trixie`,
          expect.stringContaining('glab artifact-registry login'),
        ]);
      });
    });
  });

  describe('a manifest reference no registry could serve', () => {
    const buildContainer = (rest) =>
      setupSnippetSections({
        format: 'DOCKER',
        tool: 'docker',
        section: SETUP_SECTION_INSTALL,
        name: NAME,
        repositoryUrl: urlFor('DOCKER'),
        ...rest,
      });

    it.each`
      case                   | digest
      ${'uppercase hex'}     | ${`sha256:${'A1B2C3D4'.repeat(8)}`}
      ${'another algorithm'} | ${`sha512:${'a1b2c3d4'.repeat(8)}`}
      ${'a truncated hex'}   | ${'sha256:a1b2c3d4'}
      ${'no algorithm'}      | ${'a1b2c3d4'.repeat(8)}
      ${'a shell payload'}   | ${`sha256:${'a1b2c3d4'.repeat(8)}; rm -rf /`}
      ${'a non-string'}      | ${42}
    `('yields no sections for $case', ({ digest }) => {
      expect(buildContainer({ imageName: 'payment-service', digest })).toEqual([]);
    });

    it.each(['imageName', 'tag'])('yields no sections for a hostile %s', (field) => {
      expect(buildContainer({ [field]: 'a; rm -rf /', digest: DIGEST })).toEqual([]);
    });
  });

  describe('a coordinate no artifact could carry', () => {
    const HOSTILE = {
      xml: 'a</groupId><evil>x</evil><groupId>b',
      groovyQuote: "1.0'; System.exit(0); '",
      kotlinQuote: '1.0"); System.exit(0); ("',
      kotlinTemplate: '1.0-$buildDir',
      backslash: 'a\\b',
      shell: 'pkg; rm -rf /',
      space: 'com.company app',
    };

    const buildWith = (coordinates, { format = 'MAVEN', tool = 'maven' } = {}) =>
      setupSnippetSections({
        format,
        tool,
        section: SETUP_SECTION_INSTALL,
        name: NAME,
        repositoryUrl: urlFor(format),
        ...coordinates,
      });

    it.each(Object.entries(HOSTILE))('yields no sections for a groupId carrying %s', (_, value) => {
      expect(buildWith({ groupId: value })).toEqual([]);
    });

    it.each(['artifactId', 'version'])('yields no sections for a hostile %s', (field) => {
      expect(buildWith({ [field]: HOSTILE.xml })).toEqual([]);
    });

    it('yields no sections for a hostile npm package name', () => {
      expect(buildWith({ packageName: HOSTILE.shell }, { format: 'NPM', tool: 'npm' })).toEqual([]);
    });

    it.each(['maven', 'gradle_groovy', 'gradle_kotlin'])(
      'refuses it on %s, so no tool renders it',
      (tool) => {
        expect(buildWith({ version: HOSTILE.groovyQuote }, { tool })).toEqual([]);
      },
    );

    it('refuses an empty coordinate rather than composing a hole into the snippet', () => {
      expect(buildWith({ artifactId: '' })).toEqual([]);
    });

    it.each([
      ['null, which GraphQL sends for an unset field', null],
      ['a number', 2.4],
      ['a boolean', false],
    ])('refuses a version that is %s rather than falling back to the placeholder', (_, value) => {
      expect(buildWith({ version: value })).toEqual([]);
    });

    it('refuses a null npm package name', () => {
      expect(buildWith({ packageName: null }, { format: 'NPM', tool: 'npm' })).toEqual([]);
    });
  });

  describe('a coordinate a real artifact can hold', () => {
    const buildWith = (coordinates, { format = 'MAVEN', tool = 'maven' } = {}) =>
      codeOf(
        setupSnippetSections({
          format,
          tool,
          section: SETUP_SECTION_INSTALL,
          name: NAME,
          repositoryUrl: urlFor(format),
          ...coordinates,
        }),
      );

    it.each([
      [
        'a dotted group',
        { groupId: 'com.company.payment' },
        `<dependency>
  <groupId>com.company.payment</groupId>
  <artifactId>app</artifactId>
  <version>1.0.0</version>
</dependency>`,
      ],
      [
        'a hyphenated artifact',
        { artifactId: 'core-api' },
        `<dependency>
  <groupId>com.company</groupId>
  <artifactId>core-api</artifactId>
  <version>1.0.0</version>
</dependency>`,
      ],
      [
        'an underscored artifact',
        { artifactId: 'core_api' },
        `<dependency>
  <groupId>com.company</groupId>
  <artifactId>core_api</artifactId>
  <version>1.0.0</version>
</dependency>`,
      ],
      [
        'a prerelease version',
        { version: '2.4.1-rc.1' },
        `<dependency>
  <groupId>com.company</groupId>
  <artifactId>app</artifactId>
  <version>2.4.1-rc.1</version>
</dependency>`,
      ],
      [
        'a build-metadata version',
        { version: '2.4.1+build.7' },
        `<dependency>
  <groupId>com.company</groupId>
  <artifactId>app</artifactId>
  <version>2.4.1+build.7</version>
</dependency>`,
      ],
      [
        'a SNAPSHOT version',
        { version: '2.4.1-SNAPSHOT' },
        `<dependency>
  <groupId>com.company</groupId>
  <artifactId>app</artifactId>
  <version>2.4.1-SNAPSHOT</version>
</dependency>`,
      ],
    ])('composes the Maven dependency for %s', (_, coordinates, dependency) => {
      const [actual] = buildWith(coordinates);

      expect(actual).toBe(dependency);
    });

    it('composes the npm install command for a scoped package', () => {
      const [install] = buildWith(
        { packageName: '@company/design-system', version: '4.2.0' },
        { format: 'NPM', tool: 'npm' },
      );

      expect(install).toBe('npm install @company/design-system@4.2.0');
    });
  });

  describe.each(['VIRTUAL', 'REMOTE'])('on a %s repository', (kind) => {
    const buildFor = ({ format, tool }) =>
      build({ format, kind, tool, section: SETUP_SECTION_INSTALL });

    it.each`
      format     | tool               | heading               | closing
      ${'NPM'}   | ${'npm'}           | ${'Registry setup'}   | ${'Packages that use the default registry now resolve through this repository. Scope-specific registry settings still apply.'}
      ${'NPM'}   | ${'pnpm'}          | ${'Registry setup'}   | ${'Packages that use the default registry now resolve through this repository. Scope-specific registry settings still apply.'}
      ${'MAVEN'} | ${'maven'}         | ${'Repository setup'} | ${'Dependencies your build would fetch from Maven Central now resolve through this repository.'}
      ${'MAVEN'} | ${'gradle_groovy'} | ${'Repository setup'} | ${'Dependencies your build would fetch from Maven Central now resolve through this repository.'}
      ${'MAVEN'} | ${'gradle_kotlin'} | ${'Repository setup'} | ${'Dependencies your build would fetch from Maven Central now resolve through this repository.'}
      ${'MAVEN'} | ${'sbt'}           | ${'Repository setup'} | ${'Dependencies your build would fetch from Maven Central now resolve through this repository.'}
    `(
      'gives $tool only the setup, with no placeholder package to install',
      ({ format, tool, heading, closing }) => {
        const sections = buildFor({ format, tool });

        expect(sections.map((section) => section.heading)).toEqual([heading]);
        expect(textOf(sections).at(-1)).toBe(closing);
      },
    );

    it('gives yarn the setup with no closing default-registry line', () => {
      const sections = buildFor({ format: 'NPM', tool: 'yarn' });

      expect(sections.map((section) => section.heading)).toEqual(['Registry setup']);
      expect(textOf(sections)).not.toContain(
        'Packages that use the default registry now resolve through this repository. Scope-specific registry settings still apply.',
      );
    });

    it.each(['npm', 'pnpm'])('points %s at the repository as its default registry', (tool) => {
      const sections = buildFor({ format: 'NPM', tool });

      expect(codeOf(sections)).toContain(
        'registry=https://artifact-registry.example.com/acme/npm/my-repository/',
      );
      expect(textOf(sections)).toContain(
        'Set this repository as your default registry in your %{codeStart}~/.npmrc%{codeEnd} file:',
      );
    });

    it('points yarn at the repository as its default registry, not one scope', () => {
      const sections = buildFor({ format: 'NPM', tool: 'yarn' });

      expect(codeOf(sections)).toEqual([
        `npmRegistryServer: "https://artifact-registry.example.com/acme/npm/my-repository/"
npmRegistries:
  "https://artifact-registry.example.com/acme/npm/my-repository/":
    npmAlwaysAuth: true
    npmAuthToken: "\${ARTIFACT_REGISTRY_TOKEN:-}"`,
        'export ARTIFACT_REGISTRY_TOKEN="$(glab artifact-registry get-token)"',
      ]);
      expect(textOf(sections)).toContain(
        'Yarn 2.0 and later read registry settings from %{codeStart}.yarnrc.yml%{codeEnd}. To set this repository as your default registry, add this to that file:',
      );
    });

    it('mirrors Maven Central under the alias glab registers credentials for', () => {
      const sections = buildFor({ format: 'MAVEN', tool: 'maven' });

      expect(codeOf(sections)).toContain(`<mirrors>
  <mirror>
    <id>ar-acme.my-repository</id>
    <url>https://artifact-registry.example.com/acme/maven/my-repository</url>
    <mirrorOf>central</mirrorOf>
  </mirror>
</mirrors>`);
      expect(textOf(sections)).toContain(
        'To replace Maven Central, merge this configuration into your %{codeStart}~/.m2/settings.xml%{codeEnd} file:',
      );
    });

    it('enables Maven snapshots outside the Central mirror using the authenticated alias', () => {
      const [setup] = buildFor({ format: 'MAVEN', tool: 'maven' });

      expect(setup.blocks).toContainEqual({
        text: 'To also resolve snapshot dependencies, merge this configuration into your %{codeStart}pom.xml%{codeEnd} file:',
        code: `<repositories>
  <repository>
    <id>ar-acme.my-repository</id>
    <url>https://artifact-registry.example.com/acme/maven/my-repository</url>
    <snapshots>
      <enabled>true</enabled>
    </snapshots>
  </repository>
</repositories>`,
        copyText: 'Copy the snapshot repository configuration',
      });
    });

    it.each`
      tool               | file
      ${'gradle_groovy'} | ${'build.gradle'}
      ${'gradle_kotlin'} | ${'build.gradle.kts'}
    `('tells $tool to use the repository in place of Maven Central', ({ tool, file }) => {
      expect(textOf(buildFor({ format: 'MAVEN', tool }))).toContain(
        `Add the repository to your %{codeStart}${file}%{codeEnd} file in place of %{codeStart}mavenCentral()%{codeEnd}, using the values glab wrote to %{codeStart}gradle.properties%{codeEnd}:`,
      );
    });
  });

  describe.each(['DOCKER', 'OCI'])('the %s pull section', (format) => {
    it.each`
      kind         | texts
      ${'HOSTED'}  | ${['Pull an image:']}
      ${'VIRTUAL'} | ${['Pull an image:', 'For images from Docker Hub, use the full image name. Official images need the %{codeStart}library/%{codeEnd} prefix, for example %{codeStart}library/alpine%{codeEnd}.']}
      ${'REMOTE'}  | ${['Pull an image:', 'For images from Docker Hub, use the full image name. Official images need the %{codeStart}library/%{codeEnd} prefix, for example %{codeStart}library/alpine%{codeEnd}.']}
    `(
      'explains Docker Hub image names only on a non-hosted $kind repository',
      ({ kind, texts }) => {
        const [pull] = build({ format, kind, tool: 'docker', section: SETUP_SECTION_INSTALL });

        expect(textOf([pull])).toEqual(texts);
      },
    );
  });

  describe('the OCI section on oras', () => {
    const reference = `${urlFor('OCI').replace('https://', '')}/image:tag`;

    it.each`
      section                  | text                | code
      ${SETUP_SECTION_INSTALL} | ${'Pull an image:'} | ${`oras pull ${reference}`}
      ${SETUP_SECTION_PUBLISH} | ${'Push an image:'} | ${`oras push ${reference} artifact.txt`}
    `('gives the $section section its oras command', ({ section, text, code }) => {
      const [first] = build({ format: 'OCI', kind: 'HOSTED', tool: 'oras', section });

      expect(first.blocks[0]).toMatchObject({ text, code });
    });

    it('is not offered for a Docker repository', () => {
      expect(SETUP_TOOLS.DOCKER.map(({ value }) => value)).not.toContain('oras');
    });

    it('keeps Docker CLI as the default OCI tool', () => {
      expect(SETUP_TOOLS.OCI[0].value).toBe('docker');
    });
  });

  describe('when the guidance cannot be composed', () => {
    it('yields no sections without a repository URL, rather than guidance with a hole in it', () => {
      expect(
        setupSnippetSections({
          format: 'MAVEN',
          tool: 'maven',
          section: SETUP_SECTION_INSTALL,
          name: NAME,
          repositoryUrl: null,
        }),
      ).toEqual([]);
    });

    it('yields no sections without a repository name', () => {
      expect(
        setupSnippetSections({
          format: 'MAVEN',
          tool: 'maven',
          section: SETUP_SECTION_INSTALL,
          name: '',
          repositoryUrl: urlFor('MAVEN'),
        }),
      ).toEqual([]);
    });

    it('yields no sections for a format it carries no guidance for', () => {
      expect(
        setupSnippetSections({
          format: 'CONAN',
          tool: 'conan',
          section: SETUP_SECTION_INSTALL,
          name: NAME,
          repositoryUrl: urlFor('MAVEN'),
        }),
      ).toEqual([]);
    });

    it.each`
      format      | tool        | field
      ${'MAVEN'}  | ${'maven'}  | ${'groupId'}
      ${'MAVEN'}  | ${'maven'}  | ${'artifactId'}
      ${'MAVEN'}  | ${'maven'}  | ${'version'}
      ${'NPM'}    | ${'npm'}    | ${'packageName'}
      ${'DOCKER'} | ${'docker'} | ${'imageName'}
    `('yields no sections for a null $field on $format', ({ format, tool, field }) => {
      expect(
        setupSnippetSections({
          format,
          tool,
          section: SETUP_SECTION_INSTALL,
          name: NAME,
          repositoryUrl: urlFor(format),
          [field]: null,
        }),
      ).toEqual([]);
    });
  });
});

describe('installSnippetBlock', () => {
  const MAVEN_COORDINATES = {
    groupId: 'com.company.payment',
    artifactId: 'core',
    version: '2.4.1',
  };

  const NPM_COORDINATES = { packageName: '@company/design-system', version: '4.2.0' };

  const blockFor = ({ format, tool, ...coordinates }) =>
    installSnippetBlock({
      format,
      tool,
      name: NAME,
      repositoryUrl: urlFor(format),
      ...coordinates,
    });

  const INSTALL_TOOLS = ['MAVEN', 'NPM'].flatMap((format) =>
    SETUP_TOOLS[format].map(({ value: tool }) => [format, tool]),
  );

  it.each(INSTALL_TOOLS)(
    'gives a %s repository on %s the first block of its install section',
    (format, tool) => {
      const [section] = setupSnippetSections({
        format,
        tool,
        section: SETUP_SECTION_INSTALL,
        name: NAME,
        repositoryUrl: urlFor(format),
      });

      expect(blockFor({ format, tool })).toStrictEqual(section.blocks[0]);
    },
  );

  it('gives the Maven dependency declaration, not the command that follows it', () => {
    expect(blockFor({ format: 'MAVEN', tool: 'maven', ...MAVEN_COORDINATES }).code)
      .toBe(`<dependency>
  <groupId>com.company.payment</groupId>
  <artifactId>core</artifactId>
  <version>2.4.1</version>
</dependency>`);
  });

  it('gives the npm install command, not the publish command that follows it', () => {
    expect(blockFor({ format: 'NPM', tool: 'npm', ...NPM_COORDINATES }).code).toBe(
      'npm install @company/design-system@4.2.0',
    );
  });

  describe.each(['HOSTED', 'VIRTUAL', 'REMOTE'])('on a %s repository', (kind) => {
    it.each([
      {
        format: 'MAVEN',
        tool: 'maven',
        coordinates: MAVEN_COORDINATES,
        code: `<dependency>
  <groupId>com.company.payment</groupId>
  <artifactId>core</artifactId>
  <version>2.4.1</version>
</dependency>`,
      },
      {
        format: 'MAVEN',
        tool: 'gradle_groovy',
        coordinates: MAVEN_COORDINATES,
        code: "implementation 'com.company.payment:core:2.4.1'",
      },
      {
        format: 'MAVEN',
        tool: 'gradle_kotlin',
        coordinates: MAVEN_COORDINATES,
        code: 'implementation("com.company.payment:core:2.4.1")',
      },
      {
        format: 'MAVEN',
        tool: 'sbt',
        coordinates: MAVEN_COORDINATES,
        code: 'libraryDependencies += "com.company.payment" % "core" % "2.4.1"',
      },
      {
        format: 'NPM',
        tool: 'npm',
        coordinates: NPM_COORDINATES,
        code: 'npm install @company/design-system@4.2.0',
      },
      {
        format: 'NPM',
        tool: 'pnpm',
        coordinates: NPM_COORDINATES,
        code: 'pnpm add @company/design-system@4.2.0',
      },
      {
        format: 'NPM',
        tool: 'yarn',
        coordinates: NPM_COORDINATES,
        code: 'yarn add @company/design-system@4.2.0',
      },
    ])(
      'keeps the package-specific $format install block for $tool',
      ({ format, tool, coordinates, code }) => {
        expect(blockFor({ format, tool, kind, ...coordinates }).code).toBe(code);
      },
    );
  });

  it('gives a digest-addressed container its by-tag command, the first of the pair', () => {
    const host = urlFor('DOCKER').replace(/^https?:\/\//, '');
    const block = blockFor({
      format: 'DOCKER',
      tool: 'docker',
      imageName: 'payment-service',
      tag: 'trixie',
      digest: DIGEST,
    });

    expect(block.code).toBe(`docker pull ${host}/payment-service:trixie`);
    expect(block.copyText).toBe('Copy the pull-by-tag command');
  });

  it('gives an untagged container its by-digest command, the only one of the pair', () => {
    const host = urlFor('DOCKER').replace(/^https?:\/\//, '');
    const block = blockFor({
      format: 'DOCKER',
      tool: 'docker',
      imageName: 'payment-service',
      tag: null,
      digest: DIGEST,
    });

    expect(block.code).toBe(`docker pull ${host}/payment-service@${DIGEST}`);
    expect(block.copyText).toBe('Copy the pull-by-digest command');
  });

  it.each`
    format     | tool       | coordinates          | copyText
    ${'MAVEN'} | ${'maven'} | ${MAVEN_COORDINATES} | ${'Copy the dependency declaration'}
    ${'NPM'}   | ${'npm'}   | ${NPM_COORDINATES}   | ${'Copy the install command'}
  `(
    'names what the $format copy button copies, which the icon-only button needs',
    ({ format, tool, coordinates, copyText }) => {
      expect(blockFor({ format, tool, ...coordinates }).copyText).toBe(copyText);
    },
  );

  it.each`
    refusal                          | args
    ${'no repository URL'}           | ${{ repositoryUrl: null }}
    ${'no repository name'}          | ${{ name: '' }}
    ${'a format it cannot build'}    | ${{ format: 'CONAN' }}
    ${'a coordinate it cannot hold'} | ${{ groupId: 'a</groupId><evil>x</evil><groupId>b' }}
  `('gives no block for $refusal, rather than one with a hole in it', ({ args }) => {
    expect(
      installSnippetBlock({
        format: 'MAVEN',
        tool: 'maven',
        name: NAME,
        repositoryUrl: urlFor('MAVEN'),
        ...args,
      }),
    ).toBe(null);
  });
});

describe('the glab artifact-registry login command', () => {
  const glabOf = (args) =>
    codeOf(build(args)).find((code) => code.startsWith('glab artifact-registry login'));

  it('authenticates Maven under the same alias the repository block declares', () => {
    expect(glabOf({ format: 'MAVEN', tool: 'maven', section: SETUP_SECTION_INSTALL })).toBe(
      `glab artifact-registry login \\
  --maven \\
  --registry ${urlFor('MAVEN')} \\
  --registry-alias ${ALIAS}`,
    );
  });

  it.each(['gradle_groovy', 'gradle_kotlin'])('registers %s under the same alias', (tool) => {
    expect(glabOf({ format: 'MAVEN', tool, section: SETUP_SECTION_INSTALL })).toBe(
      `glab artifact-registry login \\
  --gradle \\
  --registry ${urlFor('MAVEN')} \\
  --registry-alias ${ALIAS}`,
    );
  });

  it.each`
    format     | tool      | flag     | registry
    ${'MAVEN'} | ${'sbt'}  | ${'sbt'} | ${'https://artifact-registry.example.com/acme/maven/my-repository'}
    ${'NPM'}   | ${'npm'}  | ${'npm'} | ${'https://artifact-registry.example.com/acme/npm/my-repository/'}
    ${'NPM'}   | ${'pnpm'} | ${'npm'} | ${'https://artifact-registry.example.com/acme/npm/my-repository/'}
  `(
    'logs $format in on $tool with no alias, because glab keys its entry on the registry',
    ({ format, tool, flag, registry }) => {
      expect(glabOf({ format, tool, section: SETUP_SECTION_INSTALL })).toBe(
        `glab artifact-registry login \\
  --${flag} \\
  --registry ${registry}`,
      );
    },
  );

  it.each(['DOCKER', 'OCI'])(
    'hands %s on docker the --docker flag and a bare registry host',
    (format) => {
      expect(glabOf({ format, tool: 'docker', section: SETUP_SECTION_INSTALL })).toBe(
        `glab artifact-registry login \\
  --docker \\
  --registry artifact-registry.example.com`,
      );
    },
  );

  it('signs oras in to OCI through the Docker credential helper, as docker does', () => {
    const [, oras] = build({ format: 'OCI', tool: 'oras', section: SETUP_SECTION_INSTALL });
    const [, docker] = build({ format: 'OCI', tool: 'docker', section: SETUP_SECTION_INSTALL });

    expect(oras).toEqual(docker);
  });

  it.each(['DOCKER', 'OCI'])('signs podman in to %s with a token from glab', (format) => {
    const [, setup] = build({ format, tool: 'podman', section: SETUP_SECTION_INSTALL });

    expect(setup.blocks).toEqual([
      {
        text: 'glab reads your GitLab token from %{codeStart}GITLAB_TOKEN%{codeEnd}. If that is not set, run %{codeStart}glab auth login%{codeEnd} first.',
      },
      {
        text: 'Run the following command with %{linkStart}glab%{linkEnd} 1.115 or later:',
        link: 'https://docs.gitlab.com/cli/artifact-registry/get-token/',
        code: `glab artifact-registry get-token |
  podman login artifact-registry.example.com --username __token__ --password-stdin`,
        copyText: 'Copy the glab login command',
      },
      { text: 'You cannot refresh this token. Run the command again before it expires.' },
    ]);
  });

  it('passes no duration, leaving glab to apply its own default', () => {
    everyCombination.forEach((combination) => {
      expect(glabOf(combination) ?? '').not.toContain('--duration');
    });
  });

  it.each([
    ['MAVEN', 'maven'],
    ['MAVEN', 'gradle_groovy'],
    ['MAVEN', 'gradle_kotlin'],
    ['MAVEN', 'sbt'],
    ['NPM', 'npm'],
    ['NPM', 'pnpm'],
  ])(
    'leads the setup section for %s on %s with the GitLab token, login, and expiry',
    (format, tool) => {
      const [, setup] = build({ format, tool, section: SETUP_SECTION_INSTALL });

      expect(setup.blocks.slice(0, 3).map(({ text }) => text)).toEqual([
        'glab reads your GitLab token from %{codeStart}GITLAB_TOKEN%{codeEnd}. If that is not set, run %{codeStart}glab auth login%{codeEnd} first.',
        'Run the following command with %{linkStart}glab%{linkEnd} 1.115 or later:',
        'The token lasts 15 minutes by default, and up to 12 hours if you request a longer duration. Run the command again before it expires.',
      ]);
      expect(setup.blocks[1].code).toContain('glab artifact-registry login');
    },
  );

  it.each(['DOCKER', 'OCI'])(
    'leads the %s setup section on docker with the stored credential the helper needs',
    (format) => {
      const [, setup] = build({ format, tool: 'docker', section: SETUP_SECTION_INSTALL });

      expect(setup.blocks.map(({ text }) => text)).toEqual([
        'The Docker credential helper ignores %{codeStart}GITLAB_TOKEN%{codeEnd}. If glab has no stored credential, run %{codeStart}glab auth login%{codeEnd} first.',
        'Run the following command with %{linkStart}glab%{linkEnd} 1.115 or later:',
      ]);
    },
  );

  it('links the reader to the command reference', () => {
    const [, setup] = build({ format: 'MAVEN', tool: 'maven', section: SETUP_SECTION_INSTALL });

    expect(setup.blocks[1].link).toBe('https://docs.gitlab.com/cli/artifact-registry/login/');
  });

  it('has yarn read the glab token from an environment variable, not the file', () => {
    const [, setup] = build({ format: 'NPM', tool: 'yarn', section: SETUP_SECTION_INSTALL });

    expect(setup.blocks).toEqual([
      {
        text: 'Yarn 2.0 and later read registry settings from %{codeStart}.yarnrc.yml%{codeEnd}. Add this to that file:',
        code: `npmScopes:
  scope:
    npmRegistryServer: "https://artifact-registry.example.com/acme/npm/my-repository/"
    npmAuthToken: "\${ARTIFACT_REGISTRY_TOKEN:-}"`,
        copyText: 'Copy the registry configuration',
      },
      {
        text: 'glab reads your GitLab token from %{codeStart}GITLAB_TOKEN%{codeEnd}. If that is not set, run %{codeStart}glab auth login%{codeEnd} first.',
        startsStep: true,
      },
      {
        text: 'Run the following command with %{linkStart}glab%{linkEnd} 1.115 or later:',
        link: 'https://docs.gitlab.com/cli/artifact-registry/get-token/',
        code: 'export ARTIFACT_REGISTRY_TOKEN="$(glab artifact-registry get-token)"',
        copyText: 'Copy the glab login command',
      },
      {
        text: 'The token lasts 15 minutes by default, and up to 12 hours if you request a longer duration. Run the command again before it expires.',
      },
    ]);
  });
});

describe('the registry alias', () => {
  const aliasFor = ({ slug = SLUG, name }) =>
    setupSnippetSections({
      format: 'MAVEN',
      tool: 'gradle_groovy',
      section: SETUP_SECTION_INSTALL,
      slug,
      name,
      repositoryUrl: buildRepositoryClientUrl({
        clientBaseUrl: CLIENT_BASE_URL,
        slug,
        format: 'MAVEN',
        name,
      }),
    })
      .flatMap(({ blocks }) => blocks.map(({ code }) => code))
      .join('\n')
      .match(/--registry-alias (\S+)/)?.[1];

  it.each([
    ['maven-releases', 'ar-acme.maven-releases'],
    ['maven.releases', 'ar-acme.maven.releases'],
    ['maven_releases', 'ar-acme.maven_releases'],
    ['1password-lib', 'ar-acme.1password-lib'],
    ['a', 'ar-acme.a'],
  ])('derives %s into %s', (name, expected) => {
    expect(aliasFor({ name })).toBe(expected);
  });

  it.each(['maven-releases', 'maven.releases', 'maven_releases', '1password-lib'])(
    'keeps %s inside the charset glab accepts for an alias',
    (name) => {
      expect(aliasFor({ name })).toMatch(/^[a-zA-Z0-9._-]+$/);
    },
  );

  it('gives every distinct handle and name pair its own alias, so neither overwrites the other in the files glab writes', () => {
    const pairs = [
      ['acme', 'maven-releases'],
      ['acme', 'maven.releases'],
      ['acme', 'maven_releases'],
      ['acme', 'payments'],
      ['other-org', 'payments'],
      ['acme-pay', 'ments'],
      ['acme', 'pay-ments'],
    ];
    const aliases = pairs.map(([slug, name]) => aliasFor({ slug, name }));

    expect(new Set(aliases).size).toBe(pairs.length);
  });

  it.each([
    ['gradle_groovy', "providers.gradleProperty('ar-acme.my-repositoryUrl').get()"],
    ['gradle_kotlin', 'providers.gradleProperty("ar-acme.my-repositoryUrl").get()'],
  ])('reads the %s repository from the property glab wrote under that alias', (tool, expected) => {
    const [, setup] = build({ format: 'MAVEN', tool, section: SETUP_SECTION_INSTALL });

    expect(setup.blocks.at(-1).code).toContain(expected);
  });

  it('confines a name outside the alias charset rather than passing it through', () => {
    expect(aliasFor({ name: "a';touch /tmp/pwned;'b" })).toBe('ar-acme.a-touch-tmp-pwned-b');
  });
});
