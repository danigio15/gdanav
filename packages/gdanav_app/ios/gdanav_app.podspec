# Lo stesso pezzo nativo di Package.swift, per quando Flutter usa CocoaPods.
Pod::Spec.new do |s|
  s.name             = 'gdanav_app'
  s.version          = '0.1.0'
  s.summary          = 'gdanav su iPhone: Bluetooth per il dongle OBD e CarPlay.'
  s.homepage         = 'https://github.com/danigio15/gdanav'
  s.license          = { :type => 'Proprietaria' }
  s.author           = { 'gdanav' => 'gdanav@gdahome.org' }
  s.source           = { :path => '.' }
  s.source_files     = 'gdanav_app/Sources/gdanav_app/**/*.swift'
  s.dependency 'Flutter'
  # La stessa versione di maplibre_gl.
  s.dependency 'MapLibre', '6.28.0'
  s.frameworks       = 'CarPlay', 'MapKit'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
end
