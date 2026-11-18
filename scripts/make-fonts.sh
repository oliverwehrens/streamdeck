#!/bin/bash
# Regenerates the fonts that DeckRender embeds, in Sources/CStb/fonts/.
#
# - Inter SemiBold for labels, copied from a pinned Inter release.
# - Material Symbols Outlined, as two static instances (outlined and filled) of the pinned
#   upstream variable font: wght 400, GRAD 0, opsz 48, subset to the codepoints file with no
#   layout tables. stb_truetype can apply neither variation axes nor GSUB ligatures, so names
#   are looked up through MaterialSymbols.codepoints instead.
#
# fontTools runs in a throwaway Docker container. Output is byte-identical between runs.
set -euo pipefail

cd "$(dirname "$0")/.."

MATERIAL_COMMIT="10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7"
INTER_VERSION="4.1"
FONTTOOLS_VERSION="4.60.1"
PYTHON_IMAGE="python:3.12-slim"

OUT="Sources/CStb/fonts"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

material="https://raw.githubusercontent.com/google/material-design-icons/$MATERIAL_COMMIT"
curl -sfL "$material/variablefont/MaterialSymbolsOutlined%5BFILL,GRAD,opsz,wght%5D.ttf" -o "$WORK/material.ttf"
curl -sfL "$material/variablefont/MaterialSymbolsOutlined%5BFILL,GRAD,opsz,wght%5D.codepoints" -o "$WORK/material.codepoints"
curl -sfL "$material/LICENSE" -o "$WORK/LICENSE-MaterialSymbols"

curl -sfL "https://github.com/rsms/inter/releases/download/v$INTER_VERSION/Inter-$INTER_VERSION.zip" -o "$WORK/inter.zip"
unzip -q -j "$WORK/inter.zip" "extras/ttf/Inter-SemiBold.ttf" "LICENSE.txt" -d "$WORK/inter"

cat > "$WORK/instance.py" <<'PY'
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

source, codepoints, fill, target = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
unicodes = sorted({int(line.split()[1], 16) for line in open(codepoints) if line.strip()})

font = TTFont(source, recalcTimestamp=False)
font = instancer.instantiateVariableFont(font, {"wght": 400, "GRAD": 0, "opsz": 48, "FILL": fill})

options = subset.Options()
options.layout_features = []
options.drop_tables += ["GSUB", "GPOS", "GDEF"]
options.hinting = False
options.notdef_outline = True
subsetter = subset.Subsetter(options)
subsetter.populate(unicodes=unicodes)
subsetter.subset(font)
font.save(target)
PY

docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$WORK:/work" -w /work "$PYTHON_IMAGE" sh -c "
    pip install --quiet --no-warn-script-location --target /tmp/py fonttools==$FONTTOOLS_VERSION &&
    PYTHONPATH=/tmp/py python instance.py material.ttf material.codepoints 0 MaterialSymbolsOutlined-400.ttf &&
    PYTHONPATH=/tmp/py python instance.py material.ttf material.codepoints 1 MaterialSymbolsOutlined-400-Fill.ttf
"

mkdir -p "$OUT"
cp "$WORK/MaterialSymbolsOutlined-400.ttf" "$WORK/MaterialSymbolsOutlined-400-Fill.ttf" "$OUT/"
cp "$WORK/material.codepoints" "$OUT/MaterialSymbols.codepoints"
cp "$WORK/LICENSE-MaterialSymbols" "$OUT/LICENSE-MaterialSymbols"
cp "$WORK/inter/Inter-SemiBold.ttf" "$OUT/Inter-SemiBold.ttf"
cp "$WORK/inter/LICENSE.txt" "$OUT/LICENSE-Inter"
ls -l "$OUT"
