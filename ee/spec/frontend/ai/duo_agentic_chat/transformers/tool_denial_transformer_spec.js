import { toolDenialTransformer } from 'ee/ai/duo_agentic_chat/transformers/tool_denial_transformer';

// The service stamps the tool call id on both the approval request and the tool
// message it produces once the call runs, so the two default to the same id here.
const TOOL_CALL_ID = 'toolu_01';

const makeApprovalRequest = (overrides = {}) => ({
  message_id: TOOL_CALL_ID,
  message_type: 'request',
  role: 'assistant',
  status: 'success',
  content: 'Tool create_commit requires approval. Please confirm if you want to proceed.',
  tool_info: {
    name: 'create_commit',
    args: { commit_message: 'Update README' },
  },
  ...overrides,
});

const makeExecutedTool = (overrides = {}) => ({
  message_id: TOOL_CALL_ID,
  message_type: 'tool',
  role: 'tool',
  status: 'success',
  content: 'Created commit',
  tool_info: {
    name: 'create_commit',
    args: { commit_message: 'Update README' },
  },
  ...overrides,
});

const makeAgentMessage = (overrides = {}) => ({
  message_id: 'agent-1',
  message_type: 'agent',
  role: 'assistant',
  content: 'Tool execution denied, proceeding with alternative approach',
  tool_info: null,
  ...overrides,
});

describe('toolDenialTransformer', () => {
  describe('denied approval requests', () => {
    it('converts a denied request into a cancelled request card', () => {
      const request = makeApprovalRequest();
      const result = toolDenialTransformer([request, makeAgentMessage()]);

      expect(result[0]).toMatchObject({
        message_id: TOOL_CALL_ID,
        message_type: 'request',
        role: 'assistant',
        status: 'cancelled',
        tool_info: { name: 'create_commit' },
      });
    });

    it('preserves the original tool_info and content on the converted message', () => {
      const request = makeApprovalRequest();
      const [converted] = toolDenialTransformer([request, makeAgentMessage()]);

      expect(converted.tool_info).toEqual(request.tool_info);
      expect(converted.content).toBe(request.content);
    });

    it('converts each denied request when several were denied', () => {
      const result = toolDenialTransformer([
        makeApprovalRequest({ message_id: 'toolu_01' }),
        makeApprovalRequest({ message_id: 'toolu_02' }),
        makeAgentMessage(),
      ]);

      expect(result[0].status).toBe('cancelled');
      expect(result[1].status).toBe('cancelled');
    });
  });

  describe('approved approval requests', () => {
    it('leaves a request untouched when a tool message with the same id follows it', () => {
      const request = makeApprovalRequest();
      const result = toolDenialTransformer([request, makeExecutedTool(), makeAgentMessage()]);

      expect(result[0]).toBe(request);
      expect(result[0].message_type).toBe('request');
      expect(result[0].status).toBe('success');
    });

    it('matches on the id even when the tool message args differ from the request', () => {
      const request = makeApprovalRequest();
      const executedWithDifferentArgs = makeExecutedTool({
        tool_info: { name: 'create_commit', args: { commit_message: 'normalized' } },
      });

      const result = toolDenialTransformer([request, executedWithDifferentArgs]);

      expect(result[0]).toBe(request);
    });

    it('keeps both requests approved when the same tool is requested and approved twice', () => {
      const result = toolDenialTransformer([
        makeApprovalRequest({ message_id: 'toolu_01' }),
        makeApprovalRequest({ message_id: 'toolu_02' }),
        makeExecutedTool({ message_id: 'toolu_01' }),
        makeExecutedTool({ message_id: 'toolu_02' }),
        makeAgentMessage(),
      ]);

      expect(result[0].status).toBe('success');
      expect(result[1].status).toBe('success');
    });
  });

  describe('same-name requests with different decisions', () => {
    it('cancels the denied request and keeps the approved one when the denial came first', () => {
      const result = toolDenialTransformer([
        makeApprovalRequest({ message_id: 'toolu_01' }),
        makeAgentMessage({ message_id: 'agent-1' }),
        makeApprovalRequest({ message_id: 'toolu_02' }),
        makeExecutedTool({ message_id: 'toolu_02' }),
        makeAgentMessage({ message_id: 'agent-2' }),
      ]);

      expect(result[0].status).toBe('cancelled');
      expect(result[2].status).toBe('success');
    });

    it('cancels the denied request and keeps the approved one when the approval came first', () => {
      const result = toolDenialTransformer([
        makeApprovalRequest({ message_id: 'toolu_01' }),
        makeExecutedTool({ message_id: 'toolu_01' }),
        makeApprovalRequest({ message_id: 'toolu_02' }),
        makeAgentMessage(),
      ]);

      expect(result[0].status).toBe('success');
      expect(result[2].status).toBe('cancelled');
    });
  });

  describe('streamed tool placeholders', () => {
    it('does not count a pending tool card as an approval', () => {
      const result = toolDenialTransformer([
        makeExecutedTool({ status: 'pending' }),
        makeApprovalRequest(),
        makeAgentMessage(),
      ]);

      expect(result[1].status).toBe('cancelled');
    });

    it('accepts a resolved tool card that sits before its request', () => {
      const request = makeApprovalRequest();
      const result = toolDenialTransformer([makeExecutedTool(), request, makeAgentMessage()]);

      expect(result[1]).toBe(request);
    });
  });

  describe('pending approval requests', () => {
    it('leaves a trailing pending request untouched', () => {
      const request = makeApprovalRequest();
      const result = toolDenialTransformer([makeAgentMessage(), request]);

      expect(result[1]).toBe(request);
      expect(result[1].message_type).toBe('request');
    });

    it('leaves a trailing run of multiple pending requests untouched', () => {
      const result = toolDenialTransformer([
        makeApprovalRequest({ message_id: 'toolu_01' }),
        makeApprovalRequest({ message_id: 'toolu_02' }),
      ]);

      expect(result[0].message_type).toBe('request');
      expect(result[1].message_type).toBe('request');
    });
  });

  describe('non-approval messages', () => {
    it('leaves messages without tool_info untouched', () => {
      const agent = makeAgentMessage();
      const result = toolDenialTransformer([agent]);

      expect(result[0]).toBe(agent);
    });

    it('returns an empty array unchanged', () => {
      expect(toolDenialTransformer([])).toEqual([]);
    });
  });
});
