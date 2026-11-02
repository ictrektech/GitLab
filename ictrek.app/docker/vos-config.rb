# frozen_string_literal: true

require 'uri'
url = URI.parse(ENV.fetch('GITLAB_EXTERNAL_URL'))
unless %w[http https].include?(url.scheme) && url.host && url.path == '/app/com.ictrek.gitlab' &&
    !url.userinfo && !url.query && !url.fragment
  raise 'GITLAB_EXTERNAL_URL must be an absolute URL ending in /app/com.ictrek.gitlab'
end
external_url url.to_s
nginx['listen_port'] = 80
nginx['listen_https'] = false
letsencrypt['enable'] = false
postgresql['enable'] = false
gitlab_rails['db_adapter'] = 'postgresql'
gitlab_rails['db_encoding'] = 'unicode'
gitlab_rails['db_host'] = ENV.fetch('GITLAB_DB_HOST', 'pgv')
gitlab_rails['db_port'] = 5432
gitlab_rails['db_database'] = 'gitlabhq_production'
gitlab_rails['db_username'] = 'gitlab'
gitlab_rails['db_password'] = File.read('/etc/gitlab/vos-db-password').strip
gitlab_rails['gitlab_shell_ssh_port'] = Integer(ENV.fetch('GITLAB_SSH_PORT', '2424'))
gitlab_rails['omniauth_enabled'] = true
gitlab_rails['omniauth_allow_single_sign_on'] = ['vos']
gitlab_rails['omniauth_block_auto_created_users'] = false
gitlab_rails['omniauth_auto_link_user'] = false
gitlab_rails['omniauth_auto_link_ldap_user'] = false
gitlab_rails['omniauth_allow_bypass_two_factor'] = false
gitlab_rails['omniauth_providers'] = [{
  name: 'vos', label: 'VOS',
  args: {
    strategy_class: 'OmniAuth::Strategies::Vos',
    client_id: 'com.ictrek.gitlab',
    endpoint: ENV.fetch('VOS_OIDC_ENDPOINT', 'http://172.17.0.1:8105/v1000/oauth2')
  }
}]
prometheus_monitoring['enable'] = false
gitlab_exporter['enable'] = false
alertmanager['enable'] = false
registry['enable'] = false
gitlab_pages['enable'] = false
