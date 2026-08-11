## Generate Specs for partition & non-partition modes
```go
cd internal
chmod +x generate.sh
./generate.sh partition
./generate.sh non-partition
```

#### NOTE: Size of CSI_Parent_Pool should be minimum 3 TB on both Primary & Secondary Storages