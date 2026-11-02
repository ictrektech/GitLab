// Authored here rather than reusing the app's copy, so the assertion proves the wiring
// rather than the fallback.
export const FETCH_ERROR = 'The policy configuration could not be read';

// Deliberately synthetic: which inputs the backend rejects is backend behaviour. The
// frontend's half is relaying whatever the mutation puts in `errors` into the alert.
export const SYNTHETIC_SAVE_ERROR = 'Synthetic server error for spec';

// A second message, because the editor splits the array into an alert title and a list.
export const SYNTHETIC_SECONDARY_SAVE_ERROR = 'Second synthetic server error for spec';

// Deliberately not `actions`: rule mode routes that field's errors to the action row.
export const SYNTHETIC_VALIDATION_ERROR_FIELD = 'name';

// The one field rule mode keeps out of the alert, routing it to the action row instead.
export const ACTION_VALIDATION_ERROR_FIELD = 'actions';
