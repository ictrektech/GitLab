import {
  isValidConfigurationEntity,
  isValidAnalyzerEntity,
  getAvailableScanProfiles,
} from 'ee/security_configuration/components/utils';
import { makeEntities, makeAnalyzerEntities } from '../helpers';
import { mockScanner2 } from './scan_profiles/mock_data';

describe('isValidConfigurationEntity', () => {
  const validEntities = makeEntities(3);

  const invalidEntities = [
    null,
    undefined,
    [],
    {},
    ...makeEntities(1, { field: undefined }),
    ...makeEntities(1, { type: undefined }),
    ...makeEntities(1, { description: undefined }),
    ...makeEntities(1, { label: undefined }),
    ...makeEntities(1, { value: undefined }),
  ];

  it.each(validEntities)('returns true for a valid entity', (entity) => {
    expect(isValidConfigurationEntity(entity)).toBe(true);
  });

  it.each(invalidEntities)('returns false for an invalid entity', (invalidEntity) => {
    expect(isValidConfigurationEntity(invalidEntity)).toBe(false);
  });
});

describe('isValidAnalyzerEntity', () => {
  const validEntities = makeAnalyzerEntities(3);

  const invalidEntities = [
    null,
    undefined,
    [],
    {},
    ...makeAnalyzerEntities(1, { name: undefined }),
    ...makeAnalyzerEntities(1, { label: undefined }),
    ...makeAnalyzerEntities(1, { enabled: undefined }),
    ...makeAnalyzerEntities(1, { enabled: '' }),
  ];

  it.each(validEntities)('returns true for a valid entity', (entity) => {
    expect(isValidAnalyzerEntity(entity)).toBe(true);
  });

  it.each(invalidEntities)('returns false for an invalid entity', (invalidEntity) => {
    expect(isValidAnalyzerEntity(invalidEntity)).toBe(false);
  });
});

describe('getAvailableScanProfiles', () => {
  const sastProfile = mockScanner2;
  const triageProfile = {
    ...mockScanner2,
    id: 'gid://gitlab/Security::ScanProfile/triage_and_remediation',
    scanType: 'TRIAGE_AND_REMEDIATION',
  };
  const createData = (profiles) => ({ group: { availableSecurityScanProfiles: profiles } });

  describe.each([true, false])('with the triage feature flag set to %s', (flag) => {
    it('hides a triage and remediation profile', () => {
      window.gon.features = { triageAndRemediationProfilesUi: flag };

      expect(getAvailableScanProfiles(createData([sastProfile, triageProfile]))).toEqual([
        sastProfile,
      ]);
    });
  });

  it('hides a profile with an unknown scan type', () => {
    expect(
      getAvailableScanProfiles(createData([sastProfile, { ...sastProfile, scanType: 'UNKNOWN' }])),
    ).toEqual([sastProfile]);
  });

  it('returns an empty array for a missing group', () => {
    expect(getAvailableScanProfiles({ group: null })).toEqual([]);
  });
});
