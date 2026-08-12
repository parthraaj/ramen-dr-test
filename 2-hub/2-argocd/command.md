
## Command to generate kustomize to manifests in render dir
```go
rm -rf rendered

for f in overlays/*/*/*; do
  outdir="rendered/${f#overlays/}"
  mkdir -p "$outdir"

  kustomize build "$f" > "$outdir/0-combined-manifest.yaml"

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
      if (kind == "Namespace" || kind == "ManagedClusterSetBinding" || kind == "Placement" || kind == "ConfigMap" || kind == "Role" || kind == "RoleBinding" || kind == "GitOpsCluster" || kind == "DRPolicy") {
        target = outdir "/1-gitops-prereq.yaml"
      } else if (kind == "DRPlacementControl") {
        target = outdir "/2-drpc.yaml"
      } else if (kind == "ApplicationSet") {
        target = outdir "/3-applicationset.yaml"
      } else {
        target = ""
      }
      if (target != "") {
        printf "---\n%s", doc >> target
      }
    }
  ' "$outdir/0-combined-manifest.yaml"

  echo "wrote $outdir"
done

for f in rendered/*/*/*/1-gitops-prereq.yaml rendered/*/*/*/2-drpc.yaml rendered/*/*/*/3-applicationset.yaml; do
  sed -i '' '1{/^---$/d}' "$f" 2>/dev/null
done
```