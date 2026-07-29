require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "atc-parser-kit"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = { :type => "MIT" }
  s.author       = package["author"]
  s.platforms    = { :ios => "15.0" }
  s.source       = { :git => "https://github.com/ishantve/ATCParserKit.git", :tag => "rn-#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"

  # React Native bridge + the shared Swift parser core.
  s.dependency "React-Core"
  s.dependency "ATCParserKit"
end
