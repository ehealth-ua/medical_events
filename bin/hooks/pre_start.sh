#!/bin/sh
# `pwd` should be /opt/api
APP_NAME="api"

if [ "${DB_MIGRATE}" == "true" ]; then
  echo "[WARNING] Migrating database!"
  ./bin/$APP_NAME command Elixir.Core.ReleaseTasks migrate
fi;
