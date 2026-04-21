#!/usr/bin/env sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

FLUTTER_SDK=${FLUTTER_SDK:-/home/Manu/Software/Flutter_SDK/flutter}
JAVA_HOME_DEFAULT=/home/Manu/.antigravity/extensions/redhat.java-1.12.0-linux-x64/jre/17.0.4.1-linux-x86_64
JAVA_HOME=${JAVA_HOME:-$JAVA_HOME_DEFAULT}

if [ ! -x "$FLUTTER_SDK/bin/flutter" ]; then
  echo "Flutter SDK not found at $FLUTTER_SDK" >&2
  echo "Set FLUTTER_SDK=/absolute/path/to/flutter before running this script." >&2
  exit 1
fi

if [ ! -x "$JAVA_HOME/bin/java" ]; then
  echo "Java not found at $JAVA_HOME" >&2
  echo "Set JAVA_HOME=/absolute/path/to/jdk-or-jre before running this script." >&2
  exit 1
fi

export FLUTTER_SDK
export JAVA_HOME
export PATH="$FLUTTER_SDK/bin:$JAVA_HOME/bin:$PATH"

exec "$@"
