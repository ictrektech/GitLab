# frozen_string_literal: true

# The whole-policy schema and the single-rule schema duplicate the `package_version` branch by
# design, so both include these examples. That keeps the two in lockstep: if one schema's branch
# drifts from the other, that schema's own spec fails.
#
# An includer embeds `rule` in whatever document its schema validates, and defines
# `validation_result` over that document plus `denied_pointer`, the JSON pointer to the first
# `denied` entry. That pointer is deliberately not defaulted: it shifts with the embedding, so a
# future includer that forgets it fails loudly instead of asserting someone else's path.
RSpec.shared_examples 'a package_version rule schema' do
  let(:rule) do
    { type: 'package_version', denied: [{ name: 'lodash', version: '4.17.20' }] }
  end

  def expect_errors_to_include(expected_error)
    expect(validation_result["errors"].pluck("error")).to include expected_error
  end

  specify { expect(validation_result["valid"]).to be true }

  context 'with allowed instead of denied (not permitted for package_version rules)' do
    let(:rule) { { type: 'package_version', allowed: [{ name: 'lodash', version: '4.17.21' }] } }

    specify { expect(validation_result["valid"]).to be false }
  end

  context 'with both denied and allowed' do
    let(:rule) do
      {
        type: 'package_version',
        denied: [{ name: 'lodash', version: '4.17.20' }],
        allowed: [{ name: 'lodash', version: '4.17.21' }]
      }
    end

    specify { expect(validation_result["valid"]).to be false }
  end

  context 'with exceptions (not permitted for package_version rules)' do
    let(:rule) do
      {
        type: 'package_version',
        denied: [{ name: 'lodash', version: '4.17.20' }],
        exceptions: [{ purl: 'pkg:npm/lodash@4.17.20' }]
      }
    end

    specify { expect(validation_result["valid"]).to be false }
  end

  context 'with a denied item missing version' do
    let(:rule) { { type: 'package_version', denied: [{ name: 'lodash' }] } }

    specify 'is invalid', :aggregate_failures do
      expect(validation_result["valid"]).to be false
      expect_errors_to_include("object at `#{denied_pointer}` is missing required properties: version")
    end
  end

  context 'with a denied item missing name' do
    let(:rule) { { type: 'package_version', denied: [{ version: '4.17.20' }] } }

    specify 'is invalid', :aggregate_failures do
      expect(validation_result["valid"]).to be false
      expect_errors_to_include("object at `#{denied_pointer}` is missing required properties: name")
    end
  end

  context 'with neither denied nor allowed' do
    let(:rule) { { type: 'package_version' } }

    specify { expect(validation_result["valid"]).to be false }
  end

  context 'with an empty denied list' do
    let(:rule) { { type: 'package_version', denied: [] } }

    specify { expect(validation_result["valid"]).to be false }
  end

  context 'with an invalid denied item' do
    where(:case_name, :entry) do
      [
        ['a blank name', { name: '', version: '4.17.20' }],
        ['a blank version', { name: 'lodash', version: '' }],
        ['a null name', { name: nil, version: '4.17.20' }],
        ['a null version', { name: 'lodash', version: nil }],
        ['a numeric version', { name: 'lodash', version: 4 }],
        ['a string instead of an object', 'lodash'],
        ['a name over 255 characters', { name: 'a' * 256, version: '4.17.20' }],
        ['a version over 255 characters', { name: 'lodash', version: '1' * 256 }],
        ['an extra property', { name: 'lodash', version: '4.17.20', purl: 'pkg:npm/lodash@4.17.20' }],
        ['a blank reason', { name: 'lodash', version: '4.17.20', reason: '' }],
        ['a numeric reason', { name: 'lodash', version: '4.17.20', reason: 123 }],
        ['a reason over 20 characters', { name: 'lodash', version: '4.17.20', reason: 'a' * 21 }],
        ['a reason with a line break', { name: 'lodash', version: '4.17.20', reason: "CVE-1\nCVE-2" }],
        ['a reason with a trailing line break', { name: 'lodash', version: '4.17.20', reason: "CVE-1\n" }],
        ['a reason with a carriage return', { name: 'lodash', version: '4.17.20', reason: "CVE-1\rCVE-2" }],
        ['a blank reference link', { name: 'lodash', version: '4.17.20', reference_link: '' }],
        ['a reference link without http or https',
          { name: 'lodash', version: '4.17.20', reference_link: 'ftp://example.com' }],
        ['a reference link with a line break before a valid link',
          { name: 'lodash', version: '4.17.20', reference_link: "javascript:alert(1)\nhttps://example.com" }],
        ['a reference link with only a scheme', { name: 'lodash', version: '4.17.20', reference_link: 'https://' }],
        ['a reference link with a carriage return',
          { name: 'lodash', version: '4.17.20', reference_link: "https://example.com\rx" }],
        ['a reference link that does not start with the scheme',
          { name: 'lodash', version: '4.17.20', reference_link: 'see https://example.com' }],
        ['a reference link with a trailing line break',
          { name: 'lodash', version: '4.17.20', reference_link: "https://example.com\n" }],
        ['a reference link over 2048 characters',
          { name: 'lodash', version: '4.17.20', reference_link: "https://example.com/#{'a' * 2048}" }]
      ]
    end

    with_them do
      let(:rule) { { type: 'package_version', denied: [entry] } }

      specify { expect(validation_result["valid"]).to be false }
    end
  end

  context 'with a reason and a reference link on each denied item' do
    let(:rule) do
      {
        type: 'package_version',
        denied: [
          { name: 'lodash', version: '4.17.20', reason: 'CVE-123', reference_link: 'https://example.com/CVE-123' },
          { name: 'redis', version: '4.35.09', reason: 'a' * 20 }
        ]
      }
    end

    specify { expect(validation_result["valid"]).to be true }
  end

  context 'with a plain http link and a link at the length limit' do
    let(:rule) do
      {
        type: 'package_version',
        denied: [
          { name: 'lodash', version: '4.17.20', reference_link: 'http://example.com' },
          { name: 'redis', version: '4.35.09', reference_link: "https://example.com/#{'a' * 2028}" }
        ]
      }
    end

    specify { expect(validation_result["valid"]).to be true }
  end

  context 'with several denied items at the length limits' do
    let(:rule) do
      {
        type: 'package_version',
        denied: [{ name: 'lodash', version: '4.17.20' }, { name: 'a' * 255, version: '1' * 255 }]
      }
    end

    specify { expect(validation_result["valid"]).to be true }
  end
end
