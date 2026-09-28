# Label migration maps

One file per repository: `<repo>.tsv`, tab-separated, one line per old label.

```
old-label<TAB>new-label     # rename; if new-label exists, issues are moved and old-label is deleted
old-label<TAB>-             # delete the label
```

Lines starting with `#` and empty lines are ignored. `bin/sync.sh` applies the
file before it creates the standard labels. Labels that are not in the standard
list and not in the map (for example `area:*` labels and `ci-allow`) are left alone.
