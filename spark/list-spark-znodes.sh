#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

curl -skSL \
    -H "Authorization: token=$(dcos config show core.dcos_acs_token)" \
    -H "Content-Type: application/json" \
    "$(dcos config show core.dcos_url)/exhibitor/exhibitor/v1/explorer/node?key=/" |  \
    jq -er '[ .[] | select(.key | match("spark_mesos_dispatcher")) ]' | \
    tee spark-dispatcher-znodes.json
