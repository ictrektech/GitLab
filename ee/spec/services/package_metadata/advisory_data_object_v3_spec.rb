# frozen_string_literal: true

require 'spec_helper'

# Everything the parent class does is covered in advisory_data_object_spec.rb.
# This covers the one thing v3 changes: where cvss_v4 is read from.
RSpec.describe PackageMetadata::AdvisoryDataObjectV3, feature_category: :software_composition_analysis do
  describe '.create' do
    let(:purl_type) { 'maven' }
    let(:hash) do
      {
        'advisory' => {
          'id' => 'ba714b53-57bd-4b62-96c0-eeaae1283b05',
          'source' => 'glad',
          'title' => 'veraPDF CLI has potential XXE (XML External Entity Injection) vulnerability',
          'cvss_v3' => 'CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:L/I:L/A:N',
          'cvss_v4' => 'CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N',
          'published_date' => '2024-12-02',
          'identifiers' => [
            { 'type' => 'cve', 'name' => 'CVE-2024-52800', 'value' => 'CVE-2024-52800' }
          ]
        },
        'packages' => [
          { 'name' => 'org.verapdf/verapdf-library', 'purl_type' => 'maven',
            'affected_range' => '[,1.26.2)', 'fixed_versions' => ['1.26.2'] }
        ]
      }
    end

    subject(:data_object) { described_class.create(hash, purl_type) }

    it 'reads cvss_v4 off the advisory rather than an additional_fields wrapper' do
      expect(data_object.cvss_v4).to eq('CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N')
    end

    it 'leaves cvss_v4 nil when the advisory does not carry one' do
      expect(described_class.create({ 'advisory' => hash['advisory'].except('cvss_v4'),
        'packages' => hash['packages'] }, purl_type).cvss_v4).to be_nil
    end

    # v2 put it in additional_fields; a v3 record never should, and reading it
    # from there would resurrect the wrapper this format removes.
    it 'ignores an additional_fields wrapper if one is present' do
      with_wrapper = hash.merge('additional_fields' => { 'advisory' => { 'cvss_v4' => 'CVSS:4.0/AV:L' } })

      expect(described_class.create(with_wrapper, purl_type).cvss_v4)
        .to eq('CVSS:4.0/AV:N/AC:L/AT:P/PR:N/UI:P/VC:L/VI:L/VA:N/SC:N/SI:N/SA:N')
    end

    it 'maps the shared fields the same way the v2 object does', :aggregate_failures do
      expect(data_object).to have_attributes(
        advisory_xid: 'ba714b53-57bd-4b62-96c0-eeaae1283b05',
        source_xid: 'glad',
        published_date: '2024-12-02',
        cve: 'CVE-2024-52800',
        affected_packages: [have_attributes(purl_type: 'maven', package_name: 'org.verapdf/verapdf-library',
          affected_range: '[,1.26.2)', fixed_versions: ['1.26.2'])])
    end
  end
end
