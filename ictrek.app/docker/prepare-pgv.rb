# frozen_string_literal: true

require 'pg'
require 'securerandom'
require 'fileutils'

database = 'gitlabhq_production'
role = 'gitlab'
secret_file = '/etc/gitlab/vos-db-password'
FileUtils.mkdir_p('/etc/gitlab', mode: 0o700)
connection = nil
60.times do
  connection = PG.connect(host: ENV.fetch('GITLAB_DB_HOST', 'pgv'), port: 5432,
    dbname: 'postgres', user: ENV.fetch('VOS_POSTGRES_USER', 'postgres'),
    password: ENV.fetch('VOS_POSTGRES_PASSWORD'), connect_timeout: 5)
  break
rescue PG::ConnectionBad
  sleep 2
end
raise 'PGV is unavailable' unless connection

begin
  version = connection.exec('SHOW server_version_num').getvalue(0, 0).to_i
  raise 'GitLab requires PGV PostgreSQL 17 or 18' unless (170_000...190_000).cover?(version)
  connections = connection.exec('SHOW max_connections').getvalue(0, 0).to_i
  buffers = connection.exec("SELECT pg_size_bytes(current_setting('shared_buffers'))").getvalue(0, 0).to_i
  if connections < 400 || buffers < 2 * 1024**3
    raise 'PGV needs max_connections >= 400 and shared_buffers >= 2GB before GitLab initialization. See check_pgv.py.'
  end
  connection.exec("SELECT pg_advisory_lock(hashtext('vos/gitlab/provision'))")
  existing_role = connection.exec_params(
    'SELECT rolsuper, rolcreaterole, rolcreatedb, rolreplication, rolbypassrls FROM pg_roles WHERE rolname=$1', [role]).first
  if existing_role && !File.file?(secret_file)
    raise 'The GitLab role already exists without its saved password. Restore its configuration before retrying.'
  end
  if existing_role && existing_role.values.any? { |value| value == 't' }
    raise 'The existing GitLab role has unexpected administrative privileges'
  end
  unless File.file?(secret_file)
    File.open(secret_file, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(SecureRandom.hex(32)) }
  end
  File.chmod(0o600, secret_file)
  password = File.read(secret_file).strip
  raise 'Saved database credential is empty' if password.empty?
  unless existing_role
    # Suppress statement logging for the credential-bearing bootstrap session only.
    connection.exec("SET log_statement = 'none'")
    connection.exec('SET log_min_duration_statement = -1')
    encrypted = connection.encrypt_password(password, role, 'scram-sha-256')
    connection.exec("CREATE ROLE #{connection.quote_ident(role)} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD #{connection.escape_literal(encrypted)}")
  end
  existing_db = connection.exec_params(
    'SELECT pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datname=$1', [database]).first
  raise 'The GitLab database belongs to another role' if existing_db && existing_db['owner'] != role

  unless existing_db
    connection.exec("CREATE DATABASE #{connection.quote_ident(database)} OWNER #{connection.quote_ident(role)} ENCODING 'UTF8' TEMPLATE template0")
  end
  connection.exec("REVOKE ALL ON DATABASE #{connection.quote_ident(database)} FROM PUBLIC")
  target = PG.connect(host: ENV.fetch('GITLAB_DB_HOST', 'pgv'), port: 5432, dbname: database,
    user: ENV.fetch('VOS_POSTGRES_USER', 'postgres'), password: ENV.fetch('VOS_POSTGRES_PASSWORD'), connect_timeout: 5)
  begin
    target.exec('REVOKE CREATE ON SCHEMA public FROM PUBLIC')
    %w[amcheck btree_gist pg_trgm plpgsql].each do |extension|
      target.exec("CREATE EXTENSION IF NOT EXISTS #{target.quote_ident(extension)}")
    end
    target.exec("GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO #{target.quote_ident(role)}")
  ensure
    target.close
  end
  application = PG.connect(host: ENV.fetch('GITLAB_DB_HOST', 'pgv'), port: 5432,
    dbname: database, user: role, password: password, connect_timeout: 5)
  application.close
  puts 'PGV GitLab database, dedicated role, extensions, and application login are ready'
rescue PG::Error
  warn 'PGV GitLab provisioning failed. Check database readiness, credentials, and extension availability.'
  exit 1
ensure
  connection.close
end
