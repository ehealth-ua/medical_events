#!/bin/sh
# `pwd` should be /opt/api
APP_NAME="medical_events_api"

if [ "${DB_MIGRATE}" == "true" ] && [ -f "./bin/${APP_NAME}" ]; then
  echo "[WARNING] Migrating database!"
  ./bin/$APP_NAME command Elixir.Core.ReleaseTasks migrate
fi;
