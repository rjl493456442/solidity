#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Script used for cross-platform comparison as part of the travis automation.
# Splits all test source code into multiple files, generates bytecode and
# uploads the bytecode into github.com/ethereum/solidity-test-bytecode where
# another travis job is triggered to do the actual comparison.
#
# ------------------------------------------------------------------------------
# This file is part of solidity.
#
# solidity is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# solidity is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with solidity.  If not, see <http://www.gnu.org/licenses/>
#
# (c) 2017 solidity contributors.
#------------------------------------------------------------------------------

set -e

REPO_ROOT="$(dirname "$0")"/../..

echo "Compiling all test contracts into bytecode..."
TMPDIR=$(mktemp -d)
(
    cd "$REPO_ROOT"
    REPO_ROOT=$(pwd) # make it absolute
    cd "$TMPDIR"

    "$REPO_ROOT"/scripts/isolate_tests.py "$REPO_ROOT"/test/contracts/* "$REPO_ROOT"/test/libsolidity/*EndToEnd*

    if [[ "$SOLC_EMSCRIPTEN" = "On" ]]
    then
        cp "$REPO_ROOT/build/solc/soljson.js" .
        npm install solc
        cat > solc <<EOF
#!/usr/bin/env node
var process = require('process')
var fs = require('fs')

for (var filename of process.argv.slice(2))
{
    if (filename !== undefined)
    {
        var inputs = {}
        inputs[filename] = fs.readFileSync(filename).toString()
        var result = require('solc/wrapper.js')(require('./soljson.js')).compile({sources: inputs})
        if (!'contracts' in result)
        {
            console.log(filenname + ': ERROR')
        }
        else
        {
            for (var contractName in result['contracts'])
            {
                console.log(contractName + ' ' + result['contracts'][contractName].bytecode)
            }
        }
    }
}
EOF
        chmod +x solc
        ./solc *.sol > report.txt
    else
        for f in *.sol
        do
            # Run solc and feed it into a very crude json "parser"
            $REPO_ROOT/build/solc/solc --combined-json bin "$f" 2>/dev/null | \
                sed -e 's/}/\n/g' | grep '"bin"' |
                sed -e 's/.*"\([^"]*\)":{"bin":"\([^"]*\)".*/\1 \2/' \
                 >> report.txt || true
        done
    fi

git config --global credential.helper store
ps: Add-Content "$env:USERPROFILE\.git-credentials" "https://$($env:access_token):x-oauth-basic@github.com`n"
git clone --depth 2 git@github.com:ethereum/solidity-test-bytecode.git
cd solidity-test-bytecode
git config user.name "travis"
git config user.email "chris@ethereum.org"
git clean -f -d -x

mkdir -p "$TRAVIS_COMMIT"
REPORT="$TRAVIS_COMMIT/$ZIP_SUFFIX.txt"
cp ../report.txt "$REPORT"
git add "$REPORT"
git commit -a -m "Added report $REPORT"
git push origin
