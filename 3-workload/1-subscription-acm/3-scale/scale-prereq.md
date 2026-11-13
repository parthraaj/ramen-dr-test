## Generate Specs for partition & non-partition modes
```go
cd internal
chmod +x generate.sh
./generate.sh partition
./generate.sh non-partition
```

#### NOTE: 50 PVCs x 20Gi = 1000Gi provisioned per site. Size of CSI_Parent_Pool should be minimum 1.5 TB on both Primary & Secondary Storages (leaves headroom for replication snapshots)