import {
  createUserPrompt,
  EMPTY_USER_PROMPT,
  invokedSlashCommands,
} from 'ee/ai/duo_agentic_chat/services/user_prompt';

describe('createUserPrompt', () => {
  it('defaults every field', () => {
    expect(createUserPrompt()).toEqual({
      text: '',
      slashCommands: [],
      goalFlow: null,
      attachments: [],
    });
  });

  it('keeps the parts it is given', () => {
    const slashCommands = [{ value: '/compact' }];
    const attachments = [{ id: 'a1' }];

    expect(
      createUserPrompt({
        text: 'hello',
        slashCommands,
        goalFlow: { consumerId: 42 },
        attachments,
      }),
    ).toEqual({
      text: 'hello',
      slashCommands,
      goalFlow: { consumerId: 42 },
      attachments,
    });
  });

  it('copies the arrays so a later mutation cannot reach into the prompt', () => {
    const slashCommands = [{ value: '/compact' }];
    const prompt = createUserPrompt({ slashCommands });

    slashCommands.push({ value: '/new' });

    expect(prompt.slashCommands).toHaveLength(1);
  });

  it('survives a JSON round trip, which is how the queue persists it', () => {
    const prompt = createUserPrompt({
      text: 'hello',
      slashCommands: [{ value: '/compact' }],
      goalFlow: { consumerId: 42 },
    });

    expect(JSON.parse(JSON.stringify(prompt))).toEqual(prompt);
  });
});

describe('EMPTY_USER_PROMPT', () => {
  it('is an empty prompt', () => {
    expect(EMPTY_USER_PROMPT).toEqual({
      text: '',
      slashCommands: [],
      goalFlow: null,
      attachments: [],
    });
  });
});

describe('invokedSlashCommands', () => {
  it('lists the commands the text carried, in order', () => {
    const prompt = createUserPrompt({
      text: '/compact then /any',
      slashCommands: [{ value: '/compact' }, { value: '/any' }],
    });

    expect(invokedSlashCommands(prompt)).toEqual(['/compact', '/any']);
  });

  it('lists /goal for a goal prompt, which keeps it out of slashCommands', () => {
    const prompt = createUserPrompt({
      text: '/goal keep the pipeline green',
      goalFlow: { consumerId: 42, goal: 'keep the pipeline green' },
    });

    expect(invokedSlashCommands(prompt)).toEqual(['/goal']);
  });

  it('lists /goal once when the prompt also records the command', () => {
    const prompt = createUserPrompt({
      text: '/goal keep the pipeline green',
      slashCommands: [{ value: '/goal' }],
      goalFlow: { consumerId: 42, goal: 'keep the pipeline green' },
    });

    expect(invokedSlashCommands(prompt)).toEqual(['/goal']);
  });

  describe('when the prompt invoked a flow command', () => {
    it.each(['/flow:deploy-to-production', '/flow:acme-corp-secret-audit-42', '/flow:'])(
      'reduces %s to the bare prefix, leaving the customer-defined name out',
      (value) => {
        const prompt = createUserPrompt({ text: `${value} go`, slashCommands: [{ value }] });

        expect(invokedSlashCommands(prompt)).toEqual(['/flow:']);
      },
    );

    it('keeps a built-in command alongside it intact', () => {
      const prompt = createUserPrompt({
        text: '/flow:deploy-to-production go',
        slashCommands: [{ value: '/flow:deploy-to-production' }, { value: '/compact' }],
      });

      expect(invokedSlashCommands(prompt)).toEqual(['/flow:', '/compact']);
    });
  });

  it('lists nothing for a prompt that invoked no command', () => {
    expect(invokedSlashCommands(createUserPrompt({ text: 'what does this do?' }))).toEqual([]);
  });

  it('lists nothing when handed no prompt at all', () => {
    expect(invokedSlashCommands()).toEqual([]);
  });
});
