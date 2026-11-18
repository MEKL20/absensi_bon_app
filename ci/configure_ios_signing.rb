require 'xcodeproj'

project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |target| target.name == 'Runner' }
raise 'Runner target not found' unless runner
runner.build_configurations.each do |config|
  next unless config.name == 'Release'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = ENV.fetch('IOS_BUNDLE_ID')
  config.build_settings['DEVELOPMENT_TEAM'] = ENV.fetch('IOS_TEAM_ID')
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['CODE_SIGN_IDENTITY'] = ENV.fetch('IOS_SIGNING_IDENTITY')
  config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = ENV.fetch('IOS_PROFILE_UUID')
end
project.save
