import {
  getText,
  screen,
  waitAndClick,
  waitForAssertion,
  waitForElement,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import { mountHomePanel, findNotificationsDropdown, findDropdownToggle } from './test_setup';

// Stated independently of the mocked notification_settings responses, so a key
// dropped from the mock fails here instead of shrinking both sides at once.
const EMAIL_EVENTS = [
  'new_note',
  'new_issue',
  'reopen_issue',
  'close_issue',
  'reassign_issue',
  'issue_due',
  'new_merge_request',
  'push_to_merge_request',
  'reopen_merge_request',
  'close_merge_request',
  'reassign_merge_request',
  'merge_merge_request',
  'failed_pipeline',
  'fixed_pipeline',
  'success_pipeline',
  'moved_project',
];

const findNotificationsToggle = () => findDropdownToggle(findNotificationsDropdown());

const findListboxItem = (value) => document.querySelector(`[data-testid="listbox-item-${value}"]`);

const findEventToggle = (eventId) => {
  const row = screen.queryByTestId(`notification-setting-${eventId}`);
  return row && (row.querySelector('button') ?? row.closest('label')?.querySelector('button'));
};

const selectNotificationLevel = async (level) => {
  await waitAndClick(findNotificationsToggle);
  await waitAndClick(() => findListboxItem(level));
};

describe('Project home panel notifications dropdown', () => {
  beforeEach(() => {
    mountHomePanel();
  });

  it('changes the notification setting to on mention', async () => {
    await selectNotificationLevel('mention');

    await waitForAssertion(() =>
      expect(findListboxItem('mention').getAttribute('aria-selected')).toBe('true'),
    );
    expect(getText(findListboxItem('mention'))).toContain('On mention');
    expect(within(findNotificationsDropdown()).queryByTestId('notifications-icon')).not.toBeNull();
  });

  it('changes the notification setting to disabled', async () => {
    await selectNotificationLevel('disabled');

    await waitForAssertion(() =>
      expect(
        within(findNotificationsDropdown()).queryByTestId('notifications-off-icon'),
      ).not.toBeNull(),
    );
  });

  it('shows a checkbox per email event in the custom notifications modal', async () => {
    await selectNotificationLevel('custom');

    // The modal opens once the level update lands, then fetches the event list.
    await waitForElement(() => screen.queryByTestId('notification-setting-new_note'));

    EMAIL_EVENTS.forEach((eventId) => {
      expect(screen.queryByTestId(`notification-setting-${eventId}`)).not.toBeNull();
    });
  });

  it('updates an email event from the custom notifications modal', async () => {
    await selectNotificationLevel('custom');
    await waitForElement(() => findEventToggle('new_note'));
    expect(findEventToggle('new_note').getAttribute('aria-checked')).toBe('false');

    findEventToggle('new_note').click();

    // The toggle re-renders from the PUT response, which flips new_note on.
    await waitForAssertion(() =>
      expect(findEventToggle('new_note').getAttribute('aria-checked')).toBe('true'),
    );
  });
});

// A sibling describe rather than a nested one: mountHomePanel appends a new
// root element per call, so inheriting the default-mount beforeEach would
// mount the app twice.
describe('Project home panel notifications dropdown when project emails are disabled', () => {
  beforeEach(() => {
    mountHomePanel({ emailsDisabled: 'true' });
  });

  it('disables the dropdown toggle', async () => {
    const toggle = await waitForElement(findNotificationsToggle);
    expect(toggle.getAttribute('aria-disabled')).toBe('true');
    expect(toggle.classList.contains('disabled')).toBe(true);
  });
});
