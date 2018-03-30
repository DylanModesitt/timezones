# Package

version       = "0.1.0"
author        = "Oscar Nihlgård"
description   = "Timezone library compatible with the standard library"
license       = "MIT"

bin = @["timezones/fetchjsontimezones"]
skipDirs = @["tests"]
requires "nim >= 0.17.3"

# Tasks

task fetch, "Fetch the timezone database":
    exec "fetchjsontimezones " & paramStr(2) & " --out:./bundled_tzdb_files/" & paramStr(2) & ".json"

task test, "Run the tests":
    echo "\nRunning C tests"
    echo "==============="
    exec "nim c --hints:off -r tests/tests.nim"
    echo "\nRunning JS tests"
    echo "================"
    exec "nim js -d:nodejs --hints:off -r tests/tests.nim"
