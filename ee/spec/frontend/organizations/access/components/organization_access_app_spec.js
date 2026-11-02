import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import OrganizationAccessApp from 'ee/organizations/access/components/organization_access_app.vue';
import ResourcesTable from 'ee/organizations/access/components/resources_table.vue';
import PageHeading from '~/vue_shared/components/page_heading.vue';

describe('OrganizationAccessApp', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(OrganizationAccessApp, {
      propsData: { organizationPath: 'my-org' },
      stubs: { PageHeading },
    });
  };

  beforeEach(() => {
    createComponent();
  });

  it('renders the heading', () => {
    expect(wrapper.findByTestId('page-heading').text()).toBe('Organization access');
  });

  it('renders the description', () => {
    expect(wrapper.findComponent(PageHeading).text()).toContain(
      'Manage resource access for items at the organization level',
    );
  });

  it('renders the resources table with the organization path', () => {
    expect(wrapper.findComponent(ResourcesTable).props('organizationPath')).toBe('my-org');
  });
});
