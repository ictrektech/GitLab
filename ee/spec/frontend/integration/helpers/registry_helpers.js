import { screen, waitAndClick, within } from 'ee_jest/integration/helpers/test_helpers';

export const findShownModal = () => document.querySelector('.modal.show');

export const findSortDropdown = () => screen.queryByTestId('registry-sort-dropdown');

export const findSortDirectionButton = () =>
  findSortDropdown()?.querySelector('.sorting-direction-button') ?? null;

export const selectSortOption = async (label) => {
  findSortDropdown().querySelector('.gl-new-dropdown-toggle').click();

  await waitAndClick(() => {
    const option = within(findSortDropdown()).queryByRole('option', { name: label });
    return option?.closest('.gl-new-dropdown-contents') ? option : null;
  });
};
