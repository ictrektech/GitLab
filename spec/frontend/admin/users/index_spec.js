import { createWrapper } from '@vue/test-utils';
import { initAdminUsersApp, initAdminUserActions } from '~/admin/users';
import AdminUsersApp from '~/admin/users/components/app.vue';
import UserActions from '~/admin/users/components/user_actions.vue';
import { users, user, paths } from './mock_data';

describe('initAdminUsersApp', () => {
  let wrapper;
  let el;

  const findApp = () => wrapper.findComponent(AdminUsersApp);

  beforeEach(() => {
    el = document.createElement('div');
    el.id = 'js-admin-users-app';
    el.dataset.users = JSON.stringify(users);
    el.dataset.paths = JSON.stringify(paths);
    document.body.appendChild(el);
  });

  afterEach(() => {
    document.body.innerHTML = '';
    el = null;
  });

  it('parses and passes props', () => {
    wrapper = createWrapper(initAdminUsersApp());

    expect(findApp().props()).toMatchObject({
      users,
      paths,
      organizationId: null,
    });
  });

  it('passes organizationId when given', () => {
    wrapper = createWrapper(initAdminUsersApp(1));

    expect(findApp().props('organizationId')).toBe(1);
  });

  it('does not mount when the element is missing', () => {
    el.remove();

    expect(initAdminUsersApp()).toBe(false);
  });
});

describe('initAdminUserActions', () => {
  let wrapper;
  let el;

  const findUserActions = () => wrapper.findComponent(UserActions);

  beforeEach(() => {
    el = document.createElement('div');
    el.dataset.user = JSON.stringify(user);
    el.dataset.paths = JSON.stringify(paths);
    document.body.appendChild(el);

    wrapper = createWrapper(initAdminUserActions(el));
  });

  afterEach(() => {
    el = null;
  });

  it('parses and passes props', () => {
    expect(findUserActions().props()).toMatchObject({
      user,
      paths,
    });
  });
});
