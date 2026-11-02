import { builders } from 'prosemirror-test-builder';
import Audio from '~/content_editor/extensions/audio';
import { createTestEditor } from '../test_utils';

describe('content_editor/extensions/audio', () => {
  let tiptapEditor;
  let doc;
  let p;
  let audio;

  beforeEach(() => {
    tiptapEditor = createTestEditor({ extensions: [Audio] });

    ({ doc, paragraph: p, audio } = builders(tiptapEditor.schema));
  });

  it('parses the controlslist attribute', () => {
    tiptapEditor.commands.setContent(
      '<span class="media-container audio-container">' +
        '<audio src="https://example.com/audio.mp3" controls controlslist="nodownload" data-title="audio"></audio>' +
        '</span>',
    );

    expect(tiptapEditor.getJSON()).toEqual(
      doc(
        p(
          audio({
            src: 'https://example.com/audio.mp3',
            alt: 'audio',
            controlsList: 'nodownload',
          }),
        ),
      ).toJSON(),
    );
  });
});
