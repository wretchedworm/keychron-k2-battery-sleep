#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/tests
swift Tests/IconChecks.swift Assets
for name in HangReader ValidReader InvalidReader; do
  clang -Wall -Wextra -Werror Tests/FixtureReader.c -o "build/tests/$name"
done
swiftc -swift-version 6 Sources/BatteryPolicy.swift Sources/SleepState.swift Sources/ReaderProcess.swift Tests/Checks.swift -o build/tests/Checks
build/tests/Checks "$PWD/build/tests"

clang -Wall -Wextra -Werror -Wno-unused-function Tests/SleepControlChecks.c -framework IOKit -framework CoreFoundation -o build/tests/SleepControlChecks
build/tests/SleepControlChecks
