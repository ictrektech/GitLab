import axios from '~/lib/utils/axios_utils';
import { buildApiUrl } from '~/api/api_utils';

const DUO_WORKFLOWS_PATH = '/api/:version/ai/duo_workflows/workflows';
const DUO_WORKFLOW_RESUME_PATH = 'resume';
const DUO_WORKFLOW_RESTART_PATH = 'restart';

export const buildWorkflowPath = (workflowId) => {
  return buildApiUrl(`${DUO_WORKFLOWS_PATH}/${workflowId}`);
};

export const buildWorkflowResumePath = (workflowId) => {
  return `${buildWorkflowPath(workflowId)}/${DUO_WORKFLOW_RESUME_PATH}`;
};

export const buildWorkflowRestartPath = (workflowId) => {
  return `${buildWorkflowPath(workflowId)}/${DUO_WORKFLOW_RESTART_PATH}`;
};

export const resumeWorkflow = async (workflowId, { humanApproval, humanMessage }) => {
  const url = buildWorkflowResumePath(workflowId);

  return axios.post(url, {
    human_approval: humanApproval,
    human_message: humanMessage,
  });
};

export const cancelWorkflow = async (workflowId) => {
  const url = buildWorkflowPath(workflowId);

  return axios.patch(url, {
    status_event: 'stop',
  });
};

export const restartWorkflow = async (workflowId) => {
  const url = buildWorkflowRestartPath(workflowId);

  return axios.post(url);
};
