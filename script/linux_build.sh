#!/bin/bash

set +e

vagrant up
vagrant ssh -- 'cd /vagrant && dmd -O -release -inline loggerd.d'
echo binary built

vagrant ssh -- 'cd /vagrant && fpm -s dir -t deb -n loggerd -v 1.0.0 --prefix /usr/local/bin loggerd'
echo debian package built
vagrant halt

