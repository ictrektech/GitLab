import { languages } from 'monaco-editor';
import { schemaDomains } from '../schema/schema_graph';
import { COMPLETION_KIND, GQL_KEYWORDS, ORBIT_GQL_LANGUAGE } from './constants';

const RELATIONSHIP_CONTEXT = /\[[^\]]*:\w*$/;
const NODE_BEFORE_RELATIONSHIP = /\(\s*(\w*)\s*(?::\s*(\w+))?[^)]*\)\s*(<?)-\s*\[[^\]]*:\w*$/;
const ENTITY_CONTEXT = /\([^){]*:\w*$/;
const PROPERTY_CONTEXT = /\b(\w+)\.\w*$/;

const MONACO_KINDS = {
  [COMPLETION_KIND.ENTITY]: languages.CompletionItemKind.Class,
  [COMPLETION_KIND.RELATIONSHIP]: languages.CompletionItemKind.Interface,
  [COMPLETION_KIND.PROPERTY]: languages.CompletionItemKind.Field,
  [COMPLETION_KIND.KEYWORD]: languages.CompletionItemKind.Keyword,
};

function boundEntityName(fullText, variable) {
  const binding = fullText.match(new RegExp(`\\(\\s*${variable}\\s*:\\s*(\\w+)`));
  return binding?.[1];
}

export function boundVariable(fullText, entityName) {
  return fullText.match(new RegExp(`\\(\\s*(\\w+)\\s*:\\s*${entityName}\\b`))?.[1];
}

function relationshipStart(textBeforeCursor, fullText) {
  const match = textBeforeCursor.match(NODE_BEFORE_RELATIONSHIP);
  if (!match) return null;

  const [, variable, label, arrow] = match;
  const entityName = label || (variable && boundEntityName(fullText, variable));
  return entityName ? { entityName, isIncoming: arrow === '<' } : null;
}

function edgesOf(edges, start) {
  if (!start) return edges;

  const startEdges = edges.filter(({ variants = [] }) =>
    variants.some(
      (variant) =>
        (start.isIncoming ? variant.target_type : variant.source_type) === start.entityName,
    ),
  );
  return startEdges.length ? startEdges : edges;
}

function relationshipCompletions({ textBeforeCursor, fullText, schema }) {
  const start = relationshipStart(textBeforeCursor, fullText);

  return edgesOf(schema.edges, start).map((edge) => ({
    label: edge.name,
    kind: COMPLETION_KIND.RELATIONSHIP,
    detail: edge.description,
  }));
}

function entityCompletions({ schema }) {
  const domainLabels = Object.fromEntries(
    schemaDomains(schema).flatMap((domain) =>
      domain.entities.map((entity) => [entity.name, domain.label]),
    ),
  );

  return schema.nodes.map((node) => ({
    label: node.name,
    kind: COMPLETION_KIND.ENTITY,
    detail: domainLabels[node.name],
    documentation: node.description,
  }));
}

function propertyCompletions({ fullText, schema }, variable) {
  const entityName = boundEntityName(fullText, variable);
  const node = schema.nodes.find(({ name }) => name === entityName);

  return (node?.properties ?? []).map((prop) => ({
    label: prop.name,
    kind: COMPLETION_KIND.PROPERTY,
    detail: prop.data_type,
  }));
}

function keywordCompletions() {
  return GQL_KEYWORDS.map((keyword) => ({ label: keyword, kind: COMPLETION_KIND.KEYWORD }));
}

export function gqlCompletions(context) {
  const { textBeforeCursor } = context;

  if (RELATIONSHIP_CONTEXT.test(textBeforeCursor)) return relationshipCompletions(context);
  if (ENTITY_CONTEXT.test(textBeforeCursor)) return entityCompletions(context);

  const property = textBeforeCursor.match(PROPERTY_CONTEXT);
  if (property) return propertyCompletions(context, property[1]);

  return keywordCompletions();
}

export function registerOrbitGqlLanguage() {
  if (languages.getLanguages().some(({ id }) => id === ORBIT_GQL_LANGUAGE)) return;

  languages.register({ id: ORBIT_GQL_LANGUAGE });
  // Only token names that every GitLab editor theme colors.
  languages.setMonarchTokensProvider(ORBIT_GQL_LANGUAGE, {
    keywords: GQL_KEYWORDS.flatMap((keyword) => keyword.split(' ')).flatMap((word) => [
      word,
      word.toLowerCase(),
    ]),
    tokenizer: {
      root: [
        [/\/\/.*$/, 'comment'],
        [/'([^'\\]|\\.)*'/, 'string'],
        [/"([^"\\]|\\.)*"/, 'string'],
        [/:[A-Z][A-Z0-9_]*\b/, 'entity.other.attribute-name'],
        [/:[A-Za-z_]\w*/, 'entity.name.tag'],
        [/\b\d+(\.\d+)?\b/, 'constant.numeric'],
        [/[A-Za-z_]\w*/, { cases: { '@keywords': 'keyword', '@default': 'identifier' } }],
      ],
    },
  });
}

export function registerOrbitGqlCompletions(getSchema) {
  return languages.registerCompletionItemProvider(ORBIT_GQL_LANGUAGE, {
    triggerCharacters: [':', '.'],
    provideCompletionItems(model, position) {
      const word = model.getWordUntilPosition(position);
      const range = {
        startLineNumber: position.lineNumber,
        endLineNumber: position.lineNumber,
        startColumn: word.startColumn,
        endColumn: word.endColumn,
      };
      const textBeforeCursor = model.getValueInRange({
        startLineNumber: 1,
        startColumn: 1,
        endLineNumber: position.lineNumber,
        endColumn: position.column,
      });

      const suggestions = gqlCompletions({
        textBeforeCursor,
        fullText: model.getValue(),
        schema: getSchema(),
      }).map(({ label, kind, detail, documentation }) => ({
        label,
        kind: MONACO_KINDS[kind],
        detail,
        documentation,
        insertText: label,
        range,
      }));

      return { suggestions };
    },
  });
}
