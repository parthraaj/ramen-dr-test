
## Command to generate kustomize to manifests in rendered dir
```go
rm -rf rendered

for f in overlays/*/*/*; do
  outdir="rendered/${f#overlays/}"
  mkdir -p "$outdir"

  # 0 - full combined manifest, exactly as kustomize builds it
  kustomize build "$f" > "$outdir/0-combined-manifest.yaml"

  # split into 1-pre-req / 2-drpc / 3-app-sub by kind, using awk
  awk -v outdir="$outdir" '
    BEGIN { doc = ""; kind = "" }
    /^---$/ {
      if (doc != "") { flush() }
      doc = ""; kind = ""
      next
    }
    {
      if ($0 ~ /^kind: /) { kind = $2 }
      doc = doc $0 "\n"
    }
    END { if (doc != "") flush() }
    function flush() {
      if (kind == "Namespace" || kind == "ManagedClusterSetBinding" || kind == "Placement" || kind == "DRPolicy") {
        target = outdir "/1-pre-req.yaml"
      } else if (kind == "DRPlacementControl") {
        target = outdir "/2-drpc.yaml"
      } else if (kind == "Application" || kind == "Subscription") {
        target = outdir "/3-app-sub.yaml"
      } else {
        target = ""
      }
      if (target != "") {
        printf "---\n%s", doc >> target
      }
    }
  ' "$outdir/0-combined-manifest.yaml"

  echo "wrote $outdir/{0-combined-manifest,1-pre-req,2-drpc,3-app-sub}.yaml"
done
```