#!/usr/bin/env bash
# Malaysia Price Watch - downloads all 15 data files into this folder.
# Mac/Linux twin of download.ps1. Run it from the repo root with:
#   bash data/download.sh
# Files that are already downloaded are skipped, so it is safe to run again.

set -u

dest="$(cd "$(dirname "$0")" && pwd)"
base="https://storage.data.gov.my/pricecatcher"

urls=()
names=()
for m in 2025-10 2025-11 2025-12 2026-01 2026-02 2026-03 2026-04 2026-05 2026-06 2026-07 2026-08 2026-09; do
  urls+=("$base/pricecatcher_$m.csv"); names+=("pricecatcher_$m.csv")
done
urls+=("$base/lookup_item.csv");                       names+=("lookup_item.csv")
urls+=("$base/lookup_premise.csv");                    names+=("lookup_premise.csv")
urls+=("https://storage.dosm.gov.my/cpi/cpi_2d_state.csv"); names+=("cpi_2d_state.csv")

total=${#urls[@]}
failed=()
for i in "${!urls[@]}"; do
  n=$((i + 1))
  url="${urls[$i]}"
  out="$dest/${names[$i]}"
  if [ -s "$out" ]; then
    echo "[$n/$total] Already have ${names[$i]}, skipping"
    continue
  fi
  echo "[$n/$total] Downloading ${names[$i]} ..."
  # -f: fail on HTTP errors (404, 500), so a broken file is never kept
  if ! curl -fL --retry 3 -sS -o "$out" "$url"; then
    echo "    FAILED: $url"
    rm -f "$out"
    failed+=("$url")
  fi
done

echo ""
echo "Files in the data folder:"
ls -lh "$dest"/*.csv 2>/dev/null || echo "  (none)"

if [ ${#failed[@]} -eq 0 ]; then
  echo "All $total files downloaded."
else
  echo "${#failed[@]} file(s) failed. Open these links in your browser and save them into this folder:"
  for u in "${failed[@]}"; do echo "  $u"; done
  exit 1
fi
