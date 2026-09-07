#!/usr/bin/env bash

set -uo pipefail

base64 -i ~/.codex/auth.json | tr -d '\n' | pbcopy
