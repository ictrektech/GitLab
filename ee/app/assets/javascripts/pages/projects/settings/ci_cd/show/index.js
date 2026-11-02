import { initGroupProtectedEnvironmentList } from 'ee/protected_environments/group_protected_environment_list';
import { initProtectedEnvironments } from 'ee/protected_environments/protected_environments';
import initPipelineSubscriptionsApp from 'ee/ci/pipeline_subscriptions';
import { initProjectSecretsApp } from 'ee/ci/secrets';
import '~/pages/projects/settings/ci_cd/show/index';

initGroupProtectedEnvironmentList();
initProtectedEnvironments();

initPipelineSubscriptionsApp();

initProjectSecretsApp(false);
