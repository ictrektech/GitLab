<script>
import { defineComponent } from 'vue';
import { GlAlert, GlButton, GlCollapsibleListbox, GlLink, GlSprintf } from '@gitlab/ui';
import { getModifierKey } from '~/constants';
import { __, formatNumber, n__, s__, sprintf } from '~/locale';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { InternalEvents } from '~/tracking';
import { DUO_CHAT_AGENT_GITLAB_DUO } from 'ee/ai/constants';
import { sendDuoChatCommand } from 'ee/ai/utils';
import { ACCESS_STATE, PURCHASE_ONLY_STATES } from 'ee/orbit/access/constants';
import ContactSalesButton from 'ee/orbit/components/trial/contact_sales_button.vue';
import {
  executeOrbitNamedQuery,
  executeOrbitQuery,
  fetchOrbitSchema,
  fetchOrbitTemplates,
} from 'ee/orbit/api/orbit_api';
import { normalizeSchema } from '../schema/schema_graph';
import QueryReferenceDrawer from './query_reference_drawer.vue';
import QueryResults from './query_results.vue';
import QuerySourceEditor from './query_source_editor.vue';
import { QUERY_ERROR_KIND, QUERY_STORAGE_KEY_PREFIX } from './constants';
import { boundVariable } from './gql_language';
import { queryErrorFor, queryResultRows } from './utils';

export default defineComponent({
  name: 'OrbitQueryEditorPage',
  components: {
    ContactSalesButton,
    GlAlert,
    GlButton,
    GlCollapsibleListbox,
    GlLink,
    GlSprintf,
    QueryReferenceDrawer,
    QueryResults,
    QuerySourceEditor,
  },
  mixins: [InternalEvents.mixin()],
  inject: [
    'adminConfigurationPath',
    'canAskDuoForQueries',
    'currentUserId',
    'queriesAvailable',
    'orbitPlatform',
  ],
  data() {
    return {
      templates: [],
      schema: normalizeSchema({}),
      queryText: '',
      isRunning: false,
      hasRun: false,
      result: null,
      queryError: null,
      isReferenceOpen: false,
      hasTemplatesError: false,
      hasNoAccess: false,
    };
  },
  computed: {
    noAccessMessage() {
      if (this.queriesAvailable) {
        return s__(
          'Orbit|To run GitLab Orbit queries, ask an Owner of your group to turn on GitLab Orbit, or contact sales.',
        );
      }

      if (this.adminConfigurationPath) return this.adminNoAccessMessage;

      if (PURCHASE_ONLY_STATES.includes(this.instanceState)) {
        return s__(
          'Orbit|To run GitLab Orbit queries, this instance needs a purchase. Ask your administrator, or contact sales.',
        );
      }
      if (this.instanceState === ACCESS_STATE.TRIAL_ELIGIBLE) {
        return s__(
          'Orbit|To run GitLab Orbit queries, ask your administrator to start the trial for this instance.',
        );
      }

      return s__(
        'Orbit|To run GitLab Orbit queries, this instance needs a trial or a purchase. Ask your administrator, or contact sales.',
      );
    },
    instanceState() {
      return this.orbitPlatform.instance?.state;
    },
    showsContactSales() {
      return this.queriesAvailable || this.instanceState !== ACCESS_STATE.TRIAL_ELIGIBLE;
    },
    adminNoAccessMessage() {
      if (this.instanceState === ACCESS_STATE.TRIAL_ELIGIBLE) {
        return s__(
          'Orbit|Start the trial of this instance to run GitLab Orbit queries. %{linkStart}Go to GitLab Orbit settings%{linkEnd}',
        );
      }
      if (PURCHASE_ONLY_STATES.includes(this.instanceState)) {
        return s__('Orbit|Contact sales to buy GitLab Orbit and run queries.');
      }

      return s__('Orbit|GitLab Orbit queries start with a trial or a purchase. Contact sales.');
    },
    queryStorageKey() {
      return `${QUERY_STORAGE_KEY_PREFIX}:${this.currentUserId}`;
    },
    isQueryEmpty() {
      return !this.queryText.trim();
    },
    selectedTemplate() {
      return this.templates.find((template) => template.query === this.queryText);
    },
    selectedTemplateName() {
      return this.selectedTemplate?.name ?? null;
    },
    templateItems() {
      return this.templates.map(({ name, description }) => ({ value: name, text: description }));
    },
    templateToggleText() {
      return this.selectedTemplate?.description ?? s__('Orbit|Examples');
    },
    hasTemplates() {
      return this.templates.length > 0;
    },
    showsExampleButtons() {
      return this.hasTemplates && !this.hasRun;
    },
    showsExampleListbox() {
      return this.hasTemplates && this.hasRun;
    },
    ghostQuery() {
      if (!this.isQueryEmpty) return null;

      return `MATCH (me:User {id: ${this.currentUserId}}) RETURN me.username, me.name`;
    },
    queryErrorTitle() {
      return this.isInvalidQuery ? s__('Orbit|The query has an error') : '';
    },
    fixQueryButtonText() {
      return this.canAskDuoToFix ? s__('Orbit|Ask GitLab Duo to fix this query') : '';
    },
    isInvalidQuery() {
      return this.queryError.kind === QUERY_ERROR_KIND.INVALID_QUERY;
    },
    canAskDuoToFix() {
      return this.canAskDuoForQueries && this.isInvalidQuery;
    },
    resultAnnouncement() {
      if (this.isRunning || !this.result) return '';

      const count = this.result.rows.length;
      if (!count) return s__('Orbit|No rows match this query');

      return sprintf(
        n__(
          'Orbit|The query returned %{count} row.',
          'Orbit|The query returned %{count} rows.',
          count,
        ),
        { count: formatNumber(count) },
      );
    },
  },
  watch: {
    queryText(text) {
      sessionStorage.setItem(this.queryStorageKey, text);
    },
  },
  created() {
    this.queryText = sessionStorage.getItem(this.queryStorageKey) ?? '';
    this.handedOverQuery = [].concat(this.$route.query.query).find(Boolean);
    if (this.$route.query.query !== undefined) this.$router.replace({ query: {} });
  },
  mounted() {
    this.loadTemplates();
    this.loadSchema();
  },
  methods: {
    async loadTemplates() {
      try {
        const templates = await fetchOrbitTemplates(this.$apollo);
        if (templates) this.templates = templates;
        else this.hasNoAccess = true;
      } catch (error) {
        this.hasTemplatesError = true;
        this.handleLoadError(error);
      }
    },
    async loadSchema() {
      try {
        this.schema = normalizeSchema(await fetchOrbitSchema(this.$apollo));
      } catch (error) {
        this.handleLoadError(error);
      }
    },
    handleLoadError(error) {
      if (queryErrorFor(error).kind === QUERY_ERROR_KIND.NO_ACCESS) {
        this.hasNoAccess = true;
      } else {
        Sentry.captureException(error);
      }
    },
    useHandedOverQuery() {
      if (this.handedOverQuery) this.$refs.editor.replaceText(this.handedOverQuery);
    },
    useTemplate(name) {
      const template = this.templates.find((item) => item.name === name);
      this.$refs.editor.replaceText(template.query);
      this.queryText = template.query;
    },
    requestQuery() {
      if (this.selectedTemplate) return executeOrbitNamedQuery(this.selectedTemplate.name);

      return executeOrbitQuery(this.queryText);
    },
    async runQuery() {
      if (this.isRunning || this.isQueryEmpty) return;

      this.trackEvent('click_orbit_execute_query');
      this.queryError = null;
      this.isRunning = true;
      const startedAt = performance.now();

      try {
        const { data } = await this.requestQuery();
        this.result = {
          rows: queryResultRows(data.result),
          durationMs: Math.round(performance.now() - startedAt),
          hasMoreRows: Boolean(data.result.pagination?.has_more),
        };
      } catch (error) {
        this.showQueryError(error);
      } finally {
        this.isRunning = false;
        this.hasRun = true;
      }
    },
    showQueryError(error) {
      this.result = null;
      this.queryError = queryErrorFor(error);
      if (this.queryError.kind === QUERY_ERROR_KIND.NO_ACCESS) this.hasNoAccess = true;
      if (this.queryError.kind === QUERY_ERROR_KIND.SERVER) Sentry.captureException(error);
    },
    insertAtCursor(text) {
      this.$refs.editor.insertText(text);
    },
    insertProperty({ entity, property }) {
      const variable = boundVariable(this.queryText, entity);
      this.insertAtCursor(variable ? `${variable}.${property}` : property);
    },
    askDuo(question) {
      sendDuoChatCommand({
        question,
        resourceId: 'orbit-query-editor',
        agenticPrompt: question,
        agent: { name: DUO_CHAT_AGENT_GITLAB_DUO },
      });
    },
    askDuoToWriteQuery() {
      this.askDuo(s__('Orbit|Help me write a GitLab Orbit GQL query. Ask me what I want to find.'));
    },
    askDuoToFixQuery() {
      const intro = sprintf(s__('Orbit|Fix this GitLab Orbit GQL query. It fails with: %{error}'), {
        error: this.queryError.message,
      });
      this.askDuo(`${intro}\n\n${this.queryText}`);
    },
    askDuoWhyNoRows() {
      const intro = s__('Orbit|Why does this GitLab Orbit GQL query return no rows?');
      this.askDuo(`${intro}\n\n${this.queryText}`);
    },
  },
  runShortcut: `${getModifierKey()}${__('Enter')}`,
});
</script>

<template>
  <div
    v-if="hasNoAccess"
    class="gl-border gl-mt-5 gl-flex gl-flex-col gl-items-start gl-gap-3 gl-rounded-xl gl-border-subtle gl-bg-subtle gl-p-5"
  >
    <p class="gl-mb-0 gl-font-bold" data-testid="query-editor-no-access">
      <gl-sprintf :message="noAccessMessage">
        <template #link="{ content }">
          <gl-link :href="adminConfigurationPath">{{ content }}</gl-link>
        </template>
      </gl-sprintf>
    </p>
    <contact-sales-button v-if="showsContactSales" glm-content="orbit-query-editor" />
  </div>
  <div v-else class="gl-flex gl-flex-col gl-gap-4 gl-pt-5" data-testid="orbit-query-editor-page">
    <query-reference-drawer
      :open="isReferenceOpen"
      :schema="schema"
      @insert="insertAtCursor"
      @insert-property="insertProperty"
      @close="isReferenceOpen = false"
    />

    <div class="gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-3">
      <div>
        <h2 class="gl-heading-4 gl-mb-1">{{ s__('Orbit|Query your graph with GQL') }}</h2>
        <p class="gl-mb-0 gl-text-subtle">
          {{
            s__(
              'Orbit|Get exact, repeatable results, like exports. Results include only data you have permission to see.',
            )
          }}
        </p>
      </div>
      <div class="gl-flex gl-flex-wrap gl-items-center gl-gap-3">
        <gl-collapsible-listbox
          v-if="showsExampleListbox"
          :items="templateItems"
          :selected="selectedTemplateName"
          :toggle-text="templateToggleText"
          data-testid="query-examples-listbox"
          @select="useTemplate"
        />
        <gl-button
          v-if="canAskDuoForQueries"
          category="secondary"
          icon="tanuki-ai"
          data-testid="write-query-with-duo"
          @click="askDuoToWriteQuery"
        >
          {{ s__('Orbit|Write it with GitLab Duo') }}
        </gl-button>
        <gl-button
          category="tertiary"
          icon="book"
          :selected="isReferenceOpen"
          :aria-expanded="String(isReferenceOpen)"
          @click="isReferenceOpen = !isReferenceOpen"
        >
          {{ s__('Orbit|Query reference') }}
        </gl-button>
      </div>
    </div>

    <gl-alert
      v-if="queryError"
      variant="danger"
      :title="queryErrorTitle"
      :primary-button-text="fixQueryButtonText"
      data-testid="query-error"
      @primary-action="askDuoToFixQuery"
      @dismiss="queryError = null"
    >
      {{ queryError.message }}
      <gl-link v-if="queryError.preferencesUrl" :href="queryError.preferencesUrl">
        {{ s__('Orbit|Go to preferences') }}
      </gl-link>
    </gl-alert>

    <div class="gl-border gl-overflow-hidden gl-rounded-lg gl-border-default">
      <query-source-editor
        ref="editor"
        :value="queryText"
        :schema="schema"
        :ghost-query="ghostQuery"
        @input="queryText = $event"
        @run="runQuery"
        @ready="useHandedOverQuery"
      />
      <div
        class="gl-border-t gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-3 gl-border-default gl-bg-subtle gl-py-2 gl-pl-4 gl-pr-2"
      >
        <span class="gl-text-sm gl-text-subtle" data-testid="query-keyboard-hint">
          <gl-sprintf v-if="ghostQuery" :message="s__('Orbit|Press %{keys} to use this query.')">
            <template #keys>
              <kbd>{{ __('Tab') }}</kbd>
            </template>
          </gl-sprintf>
          <gl-sprintf v-else :message="s__('Orbit|Press %{keys} to run.')">
            <template #keys>
              <kbd>{{ $options.runShortcut }}</kbd>
            </template>
          </gl-sprintf>
        </span>
        <gl-button
          variant="confirm"
          size="small"
          icon="play"
          :loading="isRunning"
          :disabled="isQueryEmpty"
          data-testid="run-query"
          @click="runQuery"
        >
          {{ s__('Orbit|Run query') }}
        </gl-button>
      </div>
    </div>

    <p v-if="hasTemplatesError" class="gl-mb-0 gl-text-sm gl-text-subtle">
      {{ s__('Orbit|The examples are not available. Try again later.') }}
    </p>
    <div
      v-else-if="showsExampleButtons"
      class="gl-flex gl-flex-wrap gl-items-center gl-gap-3"
      data-testid="query-example-buttons"
    >
      <span class="gl-text-sm gl-text-subtle">{{ s__('Orbit|Try an example:') }}</span>
      <gl-button
        v-for="template in templates"
        :key="template.name"
        size="small"
        @click="useTemplate(template.name)"
      >
        {{ template.description }}
      </gl-button>
    </div>

    <p class="gl-sr-only" aria-live="polite" data-testid="query-result-announcement">
      {{ resultAnnouncement }}
    </p>

    <query-results
      v-if="result"
      :rows="result.rows"
      :duration-ms="result.durationMs"
      :has-more-rows="result.hasMoreRows"
      :can-ask-duo="canAskDuoForQueries"
      @ask-duo-why="askDuoWhyNoRows"
      @check-schema="isReferenceOpen = true"
    />
  </div>
</template>
