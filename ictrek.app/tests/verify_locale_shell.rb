# frozen_string_literal: true

base = '/app/com.ictrek.gitlab'
browser = ActionDispatch::Integration::Session.new(Rack::URLMap.new(base => Rails.application))
browser.host!('gitlab.test')
browser.get("#{base}/-/vos/sign_in")
raise 'Legacy entry did not reach the integration shell' unless browser.response.redirect? && browser.response.location.end_with?("#{base}/-/vos/app")
browser.follow_redirect!
raise 'Integration shell did not render' unless browser.response.status == 200
frame = Nokogiri::HTML(browser.response.body).at_css('iframe#vos-gitlab')
raise 'Missing embedded native login entry' unless frame && frame['src'].end_with?('/-/vos/sign_in?embedded=1')
raise 'Native preferences route is incorrect' unless frame['data-preferences-url'] == "#{base}/-/profile/preferences"
raise 'Native locale choices are missing' unless JSON.parse(frame['data-locales']).include?('zh_CN')
%w[locale.js shell.css].each do |asset|
  browser.get("#{base}/-/vos/#{asset}")
  raise "Asset is unavailable: #{asset}" unless browser.response.status == 200
end
browser.get("#{base}/-/vos/sign_in?embedded=1")
raise 'Native login bootstrap did not render' unless browser.response.status == 200
raise 'Native CSRF form is missing' unless Nokogiri::HTML(browser.response.body).at_css('input[name="authenticity_token"]')
puts 'PASS: shell, legacy redirect, native routes, locales, static assets, and CSRF-protected embedded login'
