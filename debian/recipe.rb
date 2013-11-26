class Loggerd < FPM::Cookery::Recipe
  homepage 'https://github.com/codekitchen/loggerd'
  source File.expand_path('../../src', __FILE__), with: :local_path

  name 'loggerd'
  version '1.0.0'
  revision '1'

  description 'logger.c ported to D, with no maximum line length'

  def build
    safesystem 'dmd -O -inline -release loggerd.d'
  end

  def prefix(path = nil)
    current_pathname_for('usr/local')/path
  end

  def install
    bin.install ['loggerd']
  end

end
