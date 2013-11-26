Vagrant.configure("2") do |config|
  config.vm.box = "precise64"
  config.vm.hostname = "loggerd"

  config.vm.provision "shell", inline: <<-SCRIPT
  set +e
  apt-get update
  apt-get -fy install
  apt-get -y install gcc-multilib xdg-utils libcurl4-openssl-dev ruby1.9.1-dev make
  if [[ ! -f dmd_2.064.2-0_amd64.deb ]]; then
    wget -q http://downloads.dlang.org/releases/2013/dmd_2.064.2-0_amd64.deb
    dpkg -i dmd_2.064.2-0_amd64.deb
  fi
  gem install fpm-cookery --no-rdoc --no-ri
  SCRIPT
end
