import Papa from 'papaparse';
import { s__, sprintf } from '~/locale';

/**
 * Returns true when fields matches the optional header row (case-insensitive).
 *
 * @param {string[]} fields
 * @returns {boolean}
 */
function isOverridesCsvHeaderRow(fields) {
  const CSV_HEADER = ['username', 'cap', 'enabled'];
  if (fields.length !== CSV_HEADER.length) return false;
  return fields.every((f, i) => f.toLowerCase() === CSV_HEADER[i]);
}

/**
 * Parses a row of an override config
 *
 * @param {string[]} fields
 * @param {number} lineNumber
 */
function parseOverridesCsvValuesRow(fields, lineNumber) {
  if (fields.length !== 3) {
    return {
      error: sprintf(
        s__(
          'UsageBilling|Line %{lineNumber}: expected 3 comma-separated values (username, cap, enabled).',
        ),
        { lineNumber },
      ),
    };
  }

  const [username, capRaw, enabledRaw] = fields;

  if (!username) {
    return {
      error: sprintf(s__('UsageBilling|Line %{lineNumber}: username is required.'), { lineNumber }),
    };
  }

  if (username.includes('@')) {
    return {
      error: sprintf(s__('UsageBilling|Line %{lineNumber}: username must not contain "@".'), {
        lineNumber,
      }),
    };
  }

  if (!capRaw) {
    return {
      error: sprintf(s__('UsageBilling|Line %{lineNumber}: cap value is required.'), {
        lineNumber,
      }),
    };
  }

  const cap = Number(capRaw);
  if (!Number.isFinite(cap)) {
    return {
      error: sprintf(s__('UsageBilling|Line %{lineNumber}: cap must be a valid number.'), {
        lineNumber,
      }),
    };
  }

  if (cap < 0) {
    return {
      error: sprintf(s__('UsageBilling|Line %{lineNumber}: cap must not be negative.'), {
        lineNumber,
      }),
    };
  }

  // eslint-disable-next-line @gitlab/require-i18n-strings
  if (!['true', 'True', 'TRUE', 'false', 'False', 'FALSE'].includes(enabledRaw)) {
    return {
      error: sprintf(s__('UsageBilling|Line %{lineNumber}: enabled must be "true" or "false".'), {
        lineNumber,
      }),
    };
  }
  const enabled = enabledRaw.toLowerCase() === 'true';

  return { override: { username, cap, enabled } };
}

/**
 * Parses CSV text into a list of overrides or parse errors.
 *
 * Example input:
 * ```
 * alice,0,false
 * bob,999.99,true
 * carol,0,true
 * dave,1,false
 * ```
 *
 * @param {string} csvText - Raw CSV input (newline-separated rows of username,cap,enabled).
 * @return {{ overrides: Array, errors: Array<string> }}
 */
export function parseOverridesCsv(csvText) {
  const parseResults = Papa.parse(csvText, { delimiter: ',' });

  if (parseResults.errors.length) {
    return {
      overrides: [],
      errors: [s__('UsageBilling|The CSV input could not be parsed. Please check the format.')],
    };
  }

  const errors = [];
  const overrides = [];

  parseResults.data.forEach((fields, index) => {
    const lineNumber = index + 1;
    const trimmedFields = fields.map((f) => f.trim());

    // papaparse emits [''] for empty lines
    if (trimmedFields.length === 1 && !trimmedFields[0]) return;

    if (isOverridesCsvHeaderRow(trimmedFields)) {
      if (lineNumber !== 1)
        errors.push(
          sprintf(
            s__(
              'UsageBilling|Line %{lineNumber}: the CSV header should be placed on the first line.',
            ),
            { lineNumber },
          ),
        );

      return;
    }

    const { error, override } = parseOverridesCsvValuesRow(trimmedFields, lineNumber);

    if (error) {
      errors.push(error);
    } else {
      overrides.push(override);
    }
  });

  if (errors.length) return { overrides: [], errors };
  return { overrides, errors: [] };
}
