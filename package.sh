#!/usr/bin/env bash
# Package the Magisk module into an installable zip
# Usage: ./package.sh
set -e
cd "$(dirname "$0")/module"
rm -f ../MediaKeepScreenOn-v1.0.zip
zip -r ../MediaKeepScreenOn-v1.0.zip module.prop service.sh
echo "Package created: $(dirname "$0")/MediaKeepScreenOn-v1.0.zip"
