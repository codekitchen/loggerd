#!/bin/bash

set +e

vagrant up
vagrant ssh -- 'cd /vagrant/debian && fpm-cook package -t deb -p ubuntu && fpm-cook clean'
vagrant halt

