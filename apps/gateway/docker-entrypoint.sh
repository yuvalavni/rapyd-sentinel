#!/bin/sh
set -eu
envsubst '${BACKEND_HOST}' < /etc/nginx/templates/default.conf.template > /tmp/default.conf
exec nginx -g 'daemon off;'
