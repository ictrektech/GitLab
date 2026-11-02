import { serialize, builders } from '../../serialization_utils';

const { paragraph, audio } = builders;

it('correctly serializes audio', () => {
  expect(serialize(paragraph(audio({ alt: 'audio', canonicalSrc: 'audio.mp3' })))).toBe(
    `![audio](audio.mp3)`,
  );
});

it('serializes audio with controlslist', () => {
  expect(
    serialize(
      paragraph(audio({ alt: 'audio', canonicalSrc: 'audio.mp3', controlsList: 'nodownload' })),
    ),
  ).toBe(`![audio](audio.mp3){controlslist=nodownload}`);
});

it('omits controlslist values that Markdown does not support', () => {
  expect(
    serialize(paragraph(audio({ alt: 'audio', canonicalSrc: 'audio.mp3', controlsList: 'x}' }))),
  ).toBe(`![audio](audio.mp3)`);
});
