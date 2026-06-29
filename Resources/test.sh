#!/bin/bash
# Run the test suite on a machine with only Command Line Tools (no Xcode).
# On a full Xcode install, plain `swift test` works without these flags.
set -e

CLT_FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_LIBS=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

swift test \
  -Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$CLT_LIBS" \
  "$@"
