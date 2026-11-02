import { createAsyncTabContentWrapper } from './index';

export default {
  title: 'usage_quotas/components/async_tab_content_wrapper/index',
};

const Template = (component) => {
  const AsyncTabComponent = () => createAsyncTabContentWrapper(component);

  return {
    // Vue 3 also reports a failed async component to the app error handler, which
    // Storybook shows instead of the story. Stop it here, so the error component shows.
    errorCaptured: () => false,
    render(h) {
      return h(AsyncTabComponent);
    },
  };
};

export const Default = () =>
  Template(
    new Promise((resolve) => {
      setTimeout(() => {
        resolve({ template: '<div>Loaded!</div>' });
      }, 1000);
    }),
  );

export const Error = () =>
  Template(
    new Promise((resolve, reject) => {
      setTimeout(() => {
        reject(Error('null'));
      }, 1000);
    }),
  );
