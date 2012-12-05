#!/bin/sh
sudo mkdir -p /var/run/elasticsearch
sudo chown elasticsearch:elasticsearch /var/run/elasticsearch
sudo service elasticsearch restart