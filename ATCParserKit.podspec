Pod::Spec.new do |s|
  s.name             = 'ATCParserKit'
  s.version          = '1.4.0'
  s.summary          = 'ATC voice-command parser — pure Swift, cross-platform core.'
  s.description      = <<-DESC
    Parses air-traffic-control voice transcripts into a structured, JSON-ready
    result: callsign plus a typed list of commands (heading, flight level,
    altitude block, speed floor/ceiling, hold, localizer intercept).

    Also recognises your own ICAO phraseology: supply a template payload and it
    matches whatever that payload defines — several instructions and several
    aircraft in one transmission — and renders the readback to speak back.

    Context-free and dependency-free (Foundation only) — the single Swift source
    of truth behind native, React Native, and Unity integrations.
  DESC

  s.homepage         = 'https://github.com/ishantve/ATCParserKit'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Ishant' => 'ishant@zibaltech.com' }
  s.source           = { :git => 'https://github.com/ishantve/ATCParserKit.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.swift_version         = '5.9'

  s.source_files     = 'Sources/ATCParserKit/**/*.swift'
  s.frameworks       = 'Foundation'
end
