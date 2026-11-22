#!/bin/zsh
# Usage: make-build.sh <extension-dir> <Product> "<Display Name>" <bundle-id> <version>
# Writes <extension-dir>/build.sh from the notch-lab template.
set -euo pipefail
DIR=$1; PRODUCT=$2; NAME=$3; ID=$4; VERSION=$5
sed -e "s/NotchLab/$PRODUCT/g" -e "s/Notch Lab/$NAME/g" \
    -e "s/com.ibuhs.vehla.notch-lab/$ID/g" -e "s/1\.0\.1/$VERSION/g" \
    "${0:A:h}/../notch-lab/build.sh" > "$DIR/build.sh"
chmod +x "$DIR/build.sh"
