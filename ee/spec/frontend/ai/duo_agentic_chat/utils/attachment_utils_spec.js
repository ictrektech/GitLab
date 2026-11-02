import {
  ATTACHMENTS_CATEGORY,
  ALLOWED_IMAGE_MIME_TYPES,
  ATTACHMENT_REJECTION_REASONS,
  MAX_ATTACHMENTS,
  MAX_ATTACHMENT_BYTES,
  MAX_TOTAL_ATTACHMENT_BYTES,
  buildAttachmentContext,
  buildAttachments,
  dragHasSupportedFile,
  filesFromDataTransfer,
  isFileDrag,
  isSupportedAttachmentType,
  readFileAsAttachment,
} from 'ee/ai/duo_agentic_chat/utils/attachment_utils';
import { captureExceptionForDuoChat } from 'ee/ai/duo_agentic_chat/observability/sentry_utils';
import { readFileAsDataURL } from '~/lib/utils/file_utility';

// The reader is stubbed so the base64 payload is deterministic: jsdom's FileReader would
// otherwise have to actually decode the synthetic Blobs built below.
jest.mock('~/lib/utils/file_utility');
jest.mock('ee/ai/duo_agentic_chat/observability/sentry_utils');

const BASE64 = 'aGVsbG8=';

const createFile = ({ name = 'shot.png', type = 'image/png', size = 1024 } = {}) => {
  const file = new File(['x'], name, { type });
  // `size` is read-only on File, so it is redefined rather than passed in.
  Object.defineProperty(file, 'size', { value: size });
  return file;
};

describe('attachment_utils', () => {
  beforeEach(() => {
    readFileAsDataURL.mockResolvedValue(`data:image/png;base64,${BASE64}`);
  });

  describe('limits', () => {
    it('matches the limits enforced by the flow service', () => {
      // Kept in lockstep with duo_workflow_service/entities/attachments.py: a looser limit
      // here means the service silently drops the file instead of surfacing an error.
      expect(MAX_ATTACHMENTS).toBe(5);
      expect(MAX_ATTACHMENT_BYTES).toBe(2 * 1024 * 1024);
      expect(MAX_TOTAL_ATTACHMENT_BYTES).toBe(2500000);
      expect(ALLOWED_IMAGE_MIME_TYPES).toEqual(['image/png', 'image/jpeg', 'image/webp']);
    });
  });

  describe('isSupportedAttachmentType', () => {
    it.each([
      ['image/png', true],
      ['image/jpeg', true],
      // Only Anthropic/OpenAI/Bedrock take GIF; only Gemini/Vertex take HEIC.
      ['image/gif', false],
      ['image/heic', false],
      ['image/webp', true],
      ['image/svg+xml', false],
      ['application/pdf', false],
      ['', false],
    ])('returns %p for %s', (type, expected) => {
      expect(isSupportedAttachmentType(createFile({ type }))).toBe(expected);
    });

    it('does not throw on a missing file', () => {
      expect(isSupportedAttachmentType(undefined)).toBe(false);
    });
  });

  describe('readFileAsAttachment', () => {
    it('strips the data URL prefix and keeps the preview URL intact', async () => {
      const attachment = await readFileAsAttachment(createFile({ size: 12 }));

      expect(attachment).toMatchObject({
        filename: 'shot.png',
        mimeType: 'image/png',
        byteSize: 12,
        data: BASE64,
        previewUrl: `data:image/png;base64,${BASE64}`,
      });
      expect(attachment.id).toEqual(expect.any(String));
    });

    it('returns null when the reader produces a non-base64 URL', async () => {
      readFileAsDataURL.mockResolvedValue('data:image/png,notbase64');

      expect(await readFileAsAttachment(createFile())).toBeNull();
    });
  });

  describe('buildAttachments', () => {
    it('accepts supported images', async () => {
      const { attachments, errors } = await buildAttachments({ files: [createFile()] });

      expect(errors).toEqual([]);
      expect(attachments).toHaveLength(1);
    });

    it('rejects unsupported types but keeps the rest of the batch', async () => {
      const { attachments, errors } = await buildAttachments({
        files: [
          createFile({ name: 'a.png' }),
          createFile({ name: 'b.pdf', type: 'application/pdf' }),
          createFile({ name: 'c.png' }),
        ],
      });

      expect(attachments.map((a) => a.filename)).toEqual(['a.png', 'c.png']);
      expect(errors).toEqual([
        'b.pdf was not attached. Only PNG, JPEG, and WebP images are supported.',
      ]);
    });

    it('rejects a file over the per-file limit', async () => {
      const { attachments, errors } = await buildAttachments({
        files: [createFile({ name: 'big.png', size: MAX_ATTACHMENT_BYTES + 1 })],
      });

      expect(attachments).toEqual([]);
      expect(errors).toEqual(['big.png was not attached. Images must be 2.00 MiB or smaller.']);
    });

    it('rejects a file that would exceed the combined limit', async () => {
      const half = Math.ceil(MAX_TOTAL_ATTACHMENT_BYTES / 2);

      const { attachments, errors } = await buildAttachments({
        files: [
          createFile({ name: 'a.png', size: half }),
          createFile({ name: 'b.png', size: half }),
          createFile({ name: 'c.png', size: half }),
        ],
      });

      expect(attachments.map((a) => a.filename)).toEqual(['a.png', 'b.png']);
      expect(errors).toHaveLength(1);
      expect(errors[0]).toContain('c.png was not attached');
    });

    it('counts already-attached files against both limits', async () => {
      const existing = [{ byteSize: MAX_TOTAL_ATTACHMENT_BYTES - 10 }];

      const { attachments, errors } = await buildAttachments({
        files: [createFile({ name: 'a.png', size: 100 })],
        existing,
      });

      expect(attachments).toEqual([]);
      expect(errors[0]).toContain('a.png was not attached');
    });

    it('stops at the attachment count limit and reports it once', async () => {
      const files = Array.from({ length: MAX_ATTACHMENTS + 2 }, (unused, index) =>
        createFile({ name: `file-${index}.png` }),
      );

      const { attachments, errors } = await buildAttachments({ files });

      expect(attachments).toHaveLength(MAX_ATTACHMENTS);
      expect(errors).toEqual(['Uploads limited to 5 files. Some files were not attached.']);
    });

    it('reports a file that could not be read', async () => {
      readFileAsDataURL.mockResolvedValue('nonsense');

      const { attachments, errors } = await buildAttachments({
        files: [createFile({ name: 'a.png' })],
      });

      expect(attachments).toEqual([]);
      expect(errors).toEqual(['a.png could not be read and was not attached.']);
    });

    // A rejection must not escape the loop: it would take the whole batch with it,
    // discarding files already accepted and leaving the user with no error at all.
    it('keeps the rest of the batch when one file fails to read', async () => {
      readFileAsDataURL
        .mockRejectedValueOnce(new Error('unreadable'))
        .mockResolvedValue(`data:image/png;base64,${BASE64}`);

      const { attachments, errors } = await buildAttachments({
        files: [createFile({ name: 'broken.png' }), createFile({ name: 'fine.png' })],
      });

      expect(attachments.map((a) => a.filename)).toEqual(['fine.png']);
      expect(errors).toEqual(['broken.png could not be read and was not attached.']);
    });

    it('returns empty results for no files', async () => {
      expect(await buildAttachments()).toEqual({ attachments: [], errors: [], rejections: [] });
    });

    describe('rejections', () => {
      it.each`
        file                                              | reason
        ${createFile({ type: 'application/pdf' })}        | ${ATTACHMENT_REJECTION_REASONS.UNSUPPORTED_TYPE}
        ${createFile({ size: MAX_ATTACHMENT_BYTES + 1 })} | ${ATTACHMENT_REJECTION_REASONS.TOO_LARGE}
        ${createFile()}                                   | ${ATTACHMENT_REJECTION_REASONS.TOTAL_TOO_LARGE}
      `('reports $reason alongside its notice', async ({ file, reason }) => {
        const { errors, rejections } = await buildAttachments({
          files: [file],
          existing: [{ byteSize: MAX_TOTAL_ATTACHMENT_BYTES - 100 }],
        });

        expect(rejections).toEqual([{ reason, count: 1 }]);
        expect(errors).toHaveLength(1);
      });

      it('reports too_many once per batch with the number of files dropped', async () => {
        const files = Array.from({ length: MAX_ATTACHMENTS + 2 }, () => createFile());

        const { rejections } = await buildAttachments({ files });

        expect(rejections).toEqual([{ reason: ATTACHMENT_REJECTION_REASONS.TOO_MANY, count: 2 }]);
      });

      it('reports read_failed for a file that could not be read', async () => {
        readFileAsDataURL.mockResolvedValue('nonsense');

        const { rejections } = await buildAttachments({ files: [createFile()] });

        expect(rejections).toEqual([
          { reason: ATTACHMENT_REJECTION_REASONS.READ_FAILED, count: 1 },
        ]);
      });
    });

    describe('Sentry', () => {
      it('reports a read that throws', async () => {
        const error = new Error('unreadable');
        readFileAsDataURL.mockRejectedValue(error);

        await buildAttachments({ files: [createFile()] });

        expect(captureExceptionForDuoChat).toHaveBeenCalledWith(error, {
          extra: { mimeType: 'image/png' },
        });
      });

      it('reports a read that cannot be encoded as base64', async () => {
        readFileAsDataURL.mockResolvedValue('nonsense');

        await buildAttachments({ files: [createFile()] });

        expect(captureExceptionForDuoChat).toHaveBeenCalledWith(
          new Error('Duo Chat could not encode an attachment as base64'),
          { extra: { mimeType: 'image/png' } },
        );
      });

      it('reports nothing for a file rejected by the limits', async () => {
        await buildAttachments({ files: [createFile({ type: 'application/pdf' })] });

        expect(captureExceptionForDuoChat).not.toHaveBeenCalled();
      });
    });
  });

  describe('buildAttachmentContext', () => {
    it('emits one entry per attachment in the shape the flow service parses', () => {
      const attachments = [
        { mimeType: 'image/png', data: BASE64, filename: 'a.png' },
        { mimeType: 'image/webp', data: BASE64, filename: 'b.webp' },
      ];

      expect(buildAttachmentContext(attachments)).toEqual([
        {
          category: ATTACHMENTS_CATEGORY,
          content: JSON.stringify({ mime_type: 'image/png', data: BASE64, filename: 'a.png' }),
          metadata: '{}',
        },
        {
          category: ATTACHMENTS_CATEGORY,
          content: JSON.stringify({ mime_type: 'image/webp', data: BASE64, filename: 'b.webp' }),
          metadata: '{}',
        },
      ]);
    });

    it('uses snake_case keys, which is what the service reads', () => {
      const [entry] = buildAttachmentContext([
        { mimeType: 'image/png', data: BASE64, filename: 'a.png' },
      ]);

      expect(Object.keys(JSON.parse(entry.content))).toEqual(['mime_type', 'data', 'filename']);
    });

    it('returns an empty array when there is nothing attached', () => {
      expect(buildAttachmentContext()).toEqual([]);
    });
  });

  describe('filesFromDataTransfer', () => {
    // Unsupported types are kept so that buildAttachments reports them, rather than a
    // dropped PDF vanishing with no explanation.
    it('keeps unsupported types for buildAttachments to reject', () => {
      const files = [
        createFile({ name: 'a.png' }),
        createFile({ name: 'b.pdf', type: 'text/pdf' }),
      ];

      const result = filesFromDataTransfer({ files });

      expect(result.map((f) => f.name)).toEqual(['a.png', 'b.pdf']);
    });

    it('names unnamed pasted images', () => {
      const [file] = filesFromDataTransfer({
        files: [createFile({ name: '', type: 'image/webp' })],
      });

      expect(file.name).toMatch(/^image-\d+\.webp$/);
    });

    it('returns an empty array without a dataTransfer', () => {
      expect(filesFromDataTransfer(null)).toEqual([]);
      expect(filesFromDataTransfer({})).toEqual([]);
    });
  });

  describe('isFileDrag', () => {
    it.each([
      [{ dataTransfer: { types: ['Files'] } }, true],
      [{ dataTransfer: { types: ['text/plain'] } }, false],
      [{ dataTransfer: {} }, false],
      [{}, false],
      [null, false],
    ])('returns the right answer for %p', (event, expected) => {
      expect(isFileDrag(event)).toBe(expected);
    });
  });

  // Mid-drag, browsers expose MIME types and nothing else, and some expose nothing at
  // all. A file with no type (a .dmg on macOS, a folder) cannot be one of the supported
  // images, which always carry one.
  describe('dragHasSupportedFile', () => {
    const items = (...types) => types.map((type) => ({ kind: 'file', type }));

    it.each([
      ['a supported image', items('image/png'), true],
      ['a supported image among others', items('application/pdf', 'image/webp'), true],
      ['only unsupported files', items('application/pdf', 'image/gif'), false],
      ['a file of unknown type', items(''), false],
      ['no items exposed', [], true],
      ['only non-file items', [{ kind: 'string', type: 'text/plain' }], true],
    ])('with %s', (_, dragItems, expected) => {
      expect(dragHasSupportedFile({ dataTransfer: { items: dragItems } })).toBe(expected);
    });

    it('tolerates an event without a dataTransfer', () => {
      expect(dragHasSupportedFile({})).toBe(true);
      expect(dragHasSupportedFile(null)).toBe(true);
    });
  });
});
