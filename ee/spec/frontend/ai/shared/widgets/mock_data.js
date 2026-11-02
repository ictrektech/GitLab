export const mockAgentActorLinePropsWithoutAgentName = {
  sessionId: 'gid://gitlab/Ai::DuoWorkflows::Workflow/42',
  canViewSession: true,
  triggerSource: 'HUMAN',
  user: { id: 'gid://gitlab/User/7', username: 'nokafor', webPath: '/nokafor' },
};

export const mockAgentActorLineProps = {
  ...mockAgentActorLinePropsWithoutAgentName,
  agentName: 'Developer Agent',
  withAgentName: true,
};

export const mockAgentPresence = {
  agentName: 'Developer Agent',
  agentCatalogWebPath: '/-/ai/catalog/agents/3',
  sessionId: 'gid://gitlab/Ai::DuoWorkflows::Workflow/42',
  triggerSource: 'HUMAN',
  user: { id: 'gid://gitlab/User/7', username: 'nokafor', webPath: '/nokafor' },
  userPermissions: { readDuoWorkflow: true },
};
