# Repository Split Preparation - Implementation Summary

**Date**: December 2, 2025  
**Location**: `B:\git\PowerShell-Scripts\_RepoSplits\`

## Completed

All four proposed repository splits have been prepared as self-contained subfolders, ready for extraction into separate repositories.

## Created Subfolders

### 1. scanner-crc-organizer/ ✅

**Status**: Complete and ready for immediate split

**Contents:**
- 7 main scripts (PowerShell + Python)
- `CRC-FileOrganizerLib.ps1` (shared library)
- 20 test files (10 PS1 + 10 Python)
- `TestData/` folder with fixtures
- `Samples/` folder with example CSVs
- `requirements.txt` (minimal - standard library only + pytest)
- `venv_readme.md` (Python setup guide)
- `README.md` (comprehensive usage documentation)

**Self-contained**: ✓ Yes - no external dependencies except Python standard library

---

### 2. model-metadata-toolkit/ ✅

**Status**: Complete and ready for split

**Contents:**
- 7 Python scripts (GatherModelData.py, MetaDataActions.py, URL-Scraper.py, Risk*.py)
- `db_config.py` (MariaDB configuration)
- `LimitedUse/` subfolder (3 database import scripts)
- 2 README files (MetaDataActions, URL-Scraper)
- 1 test file (test_MetaDataActions.py)
- `requirements.txt` (web scraping + database packages)
- `venv_readme.md` (includes Kaggle/database setup)
- `README.md` (full toolkit documentation)

**Self-contained**: ✓ Yes - external MariaDB dependency documented

**Note**: `db_config.py` contains hardcoded credentials - migration to environment variables recommended before making public

---

### 3. brainbooks-organizer/ ✅

**Status**: Complete and ready for split

**Contents:**
- All BrainBooks/ scripts (brainbooks.py, scan_ebooks.py, process_csv.py, azw_metadata.py)
- eBook_Processing/ scripts (Sort-Book-Files.py, Match-Books-*.py, MariaDB-Import.py, etc.)
- `db_config.py` (duplicate from model-metadata-toolkit)
- 7 test files (test_calibre.py, test_author_digits.py, test_hyphens.py, etc.)
- `Documentation/`, `OL_Schemas/`, `SQL_Queries/` folders
- 4 README files (BrainBooks, eBook_Processing_Project, Match-Books-OpenLibrary, Sort-Book-Files)
- `requirements.txt` (eBook libs + web APIs + database + Kaggle)
- `venv_readme.md` (includes Kaggle API token setup)
- `README.md` (consolidated overview)

**Self-contained**: ✓ Yes - external dependencies (MariaDB, OpenLibrary API, Kaggle) documented

**Note**: Largest subfolder with most complex dependencies

---

### 4. comic-archive-tools/ ✅

**Status**: Complete and ready for split (optional)

**Contents:**
- 3 PowerShell scripts (Comic Cleanup.ps1 - 2717 lines, Comic Cleanup Rename Only, Comic Conversion)
- Embedded convention data (2000+ dates in $Jcons hashtable)
- `README.md` (full documentation with 7-Zip dependency notes)

**Self-contained**: ✓ Yes - only requires 7-Zip (Windows standard)

**Note**: No requirements.txt or venv_readme.md needed (pure PowerShell, no Python)

---

## Files NOT Included (Intentionally)

Each subfolder is **self-contained** and does **NOT** include:

❌ `.git/` folder (will be created fresh when split)  
❌ `.github/workflows/` (will be created per-repo)  
❌ `.gitignore` (will be created fresh)  
❌ Main repo's venv or cache folders  
❌ Cross-repo references or parent dependencies

## Next Steps for Repository Split

### Phase 1: High-Priority Repos (Do First)

#### scanner-crc-organizer
```powershell
# 1. Create new GitHub repo
gh repo create albyofdoom/scanner-crc-organizer --public --description "Production-grade CRC32-based file organization workflow"

# 2. Initialize and push
cd _RepoSplits\scanner-crc-organizer
git init
git add .
git commit -m "Initial commit: Split from PowerShell-Scripts"
git branch -M main
git remote add origin https://github.com/albyofdoom/scanner-crc-organizer.git
git push -u origin main

# 3. Set up GitHub Actions
# Create .github/workflows/crc-tests.yml based on original ci-tests.yml
```

#### model-metadata-toolkit
```powershell
# Same process as above
gh repo create albyofdoom/model-metadata-toolkit --public --description "Web scraping and metadata management for commercial photography"

cd _RepoSplits\model-metadata-toolkit
git init
# ... (same steps as scanner-crc-organizer)
```

### Phase 2: Medium-Priority

#### brainbooks-organizer
```powershell
gh repo create albyofdoom/brainbooks-organizer --public --description "eBook metadata extraction and intelligent file organization"

cd _RepoSplits\brainbooks-organizer
# ... (initialization steps)
```

### Phase 3: Optional

#### comic-archive-tools
```powershell
# Consider keeping in main repo OR
gh repo create albyofdoom/comic-archive-tools --public --description "Comic archive processing with Japanese convention date lookup"
```

## Main Repository Cleanup (After Split)

Once new repos are created and stable:

1. **Archive originals**: Move split folders to `_Archive/split_YYYY-MM-DD/`
2. **Update main README**: Add index linking to new repos
3. **Update copilot-instructions.md**: Reference split repos
4. **Keep shared utilities**: Functions/, Utilities/, SimpleTools/
5. **Preserve history**: Keep _Archive/ and Deprecated Versions/

## Verification Checklist

Before splitting, verify each subfolder has:

- [x] All necessary scripts copied
- [x] Test files included (where applicable)
- [x] `requirements.txt` (for Python repos)
- [x] `venv_readme.md` (for Python repos)
- [x] Comprehensive `README.md`
- [x] TestData/Samples (for scanner-crc-organizer)
- [x] No references to parent repo paths
- [x] No hardcoded absolute paths (or documented as configurable)

## Dependencies Between Split Repos

### Database Config Sharing

Both `model-metadata-toolkit` and `brainbooks-organizer` have **duplicate** `db_config.py` files:

**Recommendation**: Keep duplicates, maintain separately per-repo
- Pros: Each repo is standalone
- Cons: Credential updates must be made in both places

**Alternative**: Create shared package/submodule (adds complexity)

### Test Data

- `scanner-crc-organizer`: Has full `TestData/` and `Samples/` folders (self-contained)
- Other repos: Tests use inline fixtures or small test files

### CI/CD Workflows

Each repo will need its own `.github/workflows/*.yml`:

- `scanner-crc-organizer`: Windows CRC tests + Python pytest
- `model-metadata-toolkit`: Python pytest for scrapers
- `brainbooks-organizer`: Python pytest for parsing/matching
- `comic-archive-tools`: Optional (mainly manual testing)

## Size Estimates

| Subfolder | Approx Size | File Count |
|-----------|-------------|------------|
| scanner-crc-organizer | ~150 MB | ~30 scripts + TestData |
| model-metadata-toolkit | ~5 MB | ~10 scripts + tests |
| brainbooks-organizer | ~50 MB | ~20 scripts + Documentation |
| comic-archive-tools | ~1 MB | 3 scripts (large hashtable embedded) |

**Note**: TestData folder may be large - consider Git LFS if >100MB

## Security Considerations

⚠️ **Before making repos public**:

1. **Remove hardcoded credentials** from `db_config.py`:
   ```python
   # Change from:
   'password': 'NFdki7x*w47d@jd6'
   
   # To:
   'password': os.environ.get('DB_PASSWORD')
   ```

2. **Update documentation** to show environment variable setup

3. **Add to .gitignore**:
   ```
   db_config.py
   kaggle.json
   *.env
   ```

4. **Create example configs**:
   - `db_config.example.py`
   - `kaggle.example.json`

## Success Criteria

Each split repo should:

✅ Run independently without parent repo  
✅ Have clear, comprehensive README  
✅ Document all external dependencies  
✅ Include test suite (where applicable)  
✅ Have reproducible virtual environment  
✅ Pass CI/CD tests  
✅ Have no hardcoded credentials in commits

## Timeline Recommendation

- **Week 1**: Split scanner-crc-organizer (easiest, highest value)
- **Week 2**: Split model-metadata-toolkit
- **Week 3**: Split brainbooks-organizer (larger, more complex)
- **Week 4**: Optional comic-archive-tools split OR keep in main repo

## Rollback Plan

If issues arise after split:

1. Original files remain in main repo (until cleanup phase)
2. Can recreate split folders from originals
3. Git history preserved in main repo
4. New repos can be deleted and recreated

## Conclusion

All four proposed repository splits are prepared and ready in `_RepoSplits/` subfolder. Each is self-contained with comprehensive documentation, dependencies specified, and test suites included.

**Ready for**: Immediate extraction to separate GitHub repositories

**Recommended order**: scanner-crc-organizer → model-metadata-toolkit → brainbooks-organizer → (optional) comic-archive-tools
