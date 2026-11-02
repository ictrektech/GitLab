# frozen_string_literal: true

# Seeds the SCIM token table, which is empty in the upgrade stop dump, so migrations touching it
# were never exercised by db:migrate:multi-version-upgrade.
Gitlab::Seeder.quiet do
  puts "\nGenerating SCIM oauth access token data"

  organization = ::Gitlab::DatabaseImporters::AdminOrganizationImporter.seeded_admin_organization

  next warn "\nSkipping SCIM token seeds: no seeded organization available" unless organization
  next if ScimOauthAccessToken.for_instance.exists?

  # `before_save :ensure_token` generates and encrypts the token, so a row written straight to the
  # table would carry nothing the application could authenticate. `group` stays unset, which is the
  # instance level token the `for_instance` scope reads.
  ScimOauthAccessToken.create!(organization: organization, group: nil)
  print '.'
end
