#!/usr/bin/env bash
apt install -y nut-server
systemctl enable nut-server
systemctl enable nut-monitor
#TODO
