#!/bin/bash
# Regenerates the dark and light mode screenshots in docs/assets. Run from the clone root.
# Not part of CI. Each run saves the chosen mode in your user settings (pluginConfigs);
# the tape ends on `full`, the default.
set -e
cd "$(dirname "$0")/.."
for pair in "Catppuccin Mocha:dark" "Catppuccin Latte:light"; do
  theme="${pair%%:*}"; suffix="${pair##*:}"
  sed -e "s/THEME_NAME/$theme/" -e "s/SUFFIX/$suffix/g" demo/screens.tape.tpl > "/tmp/screens-$suffix.tape"
  vhs "/tmp/screens-$suffix.tape"
done
