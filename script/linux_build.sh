#!/bin/bash

set +e

vagrant up
vagrant ssh -- 'cd /vagrant && dmd -O -release -inline loggerd.d'
vagrant halt
echo binary built to ./loggerd
