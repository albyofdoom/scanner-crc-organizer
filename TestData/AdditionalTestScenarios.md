# Additional Test Scenarios for CRC-FileOrganizer

This document outlines additional test scenarios beyond the current test suite. These scenarios address edge cases, error conditions, and real-world failure modes that should be tested.

## Current Test Coverage (Existing)

✅ **DVD031**: Duplicate CRCs within same CSV  
✅ **DVD033**: Missing files (incomplete set)  
✅ **DVD034**: Special characters (commas, diacriticals, ampersands, long paths)  
✅ **DVD035**: Zero matches (no files found)  
✅ **DVD032**: Pre-existing completed set (should ignore)

## Proposed Additional Scenarios

### High Priority Additions

#### **TEST_MetArt-DVD036_Brackets.csv** - Square Brackets & Special Characters
**Purpose**: Test filename characters that are PowerShell wildcards  
**Files**: 10 files
- `[2024] Preview.jpg`
- `Title[Final].jpg`
- `File{Version1}.jpg`
- `Name[With]Multiple[Brackets].jpg`
- Normal files for baseline

**Expected Behavior**:
- All files matched correctly (brackets don't trigger wildcard expansion)
- `-LiteralPath` usage prevents interpretation
- CSV marked as COMPLETE and moved to completed folder

**Why Critical**: Square brackets are PowerShell wildcards. Without `-LiteralPath`, these fail to match.

---

#### **TEST_MetArt-DVD037_PathLimit.csv** - Windows Path Length Limit
**Purpose**: Test path exceeding 260 characters  
**Files**: 5 files in deeply nested structure  
**Path Structure**:
```
\very_long_folder_name_that_keeps_going\
  and_another_level_with_a_long_name\
    and_yet_another_deeply_nested_folder\
      with_even_more_nesting_to_reach_limit\
        and_finally_the_file_with_a_long_name_too.jpg (>260 total chars)
```

**Expected Behavior**:
- Script handles long paths gracefully (uses `\\?\` prefix or handles error)
- Logs warning/error for path length issues
- CSV marked incomplete if paths fail

**Why Critical**: Windows has 260-char path limit. Scripts must handle or document limitation.

---

#### **TEST_MetArt-DVD038_SharedCRC.csv** - Multiple CSVs Want Same Files
**Purpose**: Test when 2+ CSVs reference the same CRC  
**Setup**:
- DVD038 CSV references same CRCs as DVD034 (already moved)
- Files should already be in completed folder for DVD034

**Expected Behavior** (Current Script Limitation):
- Script only checks current CSV's completed folder, not other CSV folders
- DVD038 marked as INCOMPLETE (files not found in expected location)
- CSV stays in source folder
- This is **expected behavior** with current script design

**Future Enhancement**: Script could search all completed folders by CRC to detect cross-CSV duplicates.

**Why Important**: Duplicate CRCs across different CSVs are **expected and valid** in the legacy data set. They represent the same physical files legitimately referenced by multiple data collections. The script correctly rejects duplicates **within** a CSV (errors) but should allow duplicates **across** CSVs (valid legacy data structure).

---

#### **TEST_MetArt-DVD039_Conflicts.csv** - Files Exist with Wrong CRC
**Purpose**: Test when filename exists but CRC doesn't match  
**Setup**:
- File `image001.jpg` exists in source with CRC `AAAAAAAA`
- CSV expects `image001.jpg` with CRC `BBBBBBBB`

**Expected Behavior**:
- Script logs CRC mismatch
- File NOT moved (wrong file)
- CSV marked incomplete (file missing)
- Missing files CSV generated with note about mismatch

**Why Critical**: Prevents moving wrong files with same names.

---

#### **TEST_MetArt-DVD040_EmptyFolders.csv** - Empty Folder Cleanup
**Purpose**: Verify empty folders are removed after moves  
**Setup**:
- All files in a folder are moved (complete CSV)
- Source folder tree should become empty

**Expected Behavior**:
- CSV complete, all files moved
- Empty source folders removed
- Parent folders removed if also empty
- Logs show folder cleanup

**Why Critical**: Prevents accumulation of empty folder clutter.

---

### Medium Priority Additions

#### **TEST_MetArt-DVD041_MalformedCSV.csv** - Invalid CSV Structure
**Purpose**: Test handling of malformed CSV data  
**Variations** (multiple test CSVs):
- Missing CRC column entirely
- Invalid hex characters in CRC (`GGGGGGGG`)
- Wrong number of columns
- Mixed column order
- Empty lines in middle

**Expected Behavior**:
- Script validates CSV structure
- Logs descriptive error message
- Skips malformed CSV
- Continues processing other CSVs

**Why Important**: Real-world data is messy. Graceful degradation prevents crashes.

---

#### **TEST_MetArt-DVD042_ReadOnly.csv** - Read-Only Files
**Purpose**: Test handling of read-only file attributes  
**Setup**: Files with read-only attribute set

**Expected Behavior**:
- Script clears read-only attribute before move
- Files moved successfully
- Or logs error if permission denied

**Why Important**: Archive files often have read-only set.

---

#### **TEST_MetArt-DVD043_Encoding.csv** - UTF-8 with BOM
**Purpose**: Test different CSV encodings  
**Variations**:
- UTF-8 with BOM
- UTF-16 LE
- Mixed line endings (CRLF/LF)

**Expected Behavior**:
- CSV parsed correctly regardless of encoding
- No phantom characters from BOM
- Line endings handled properly

**Why Important**: CSVs from different sources have different encodings.

---

#### **TEST_MetArt-DVD044_LargeFile.csv** - Large File Handling
**Purpose**: Test performance with large files  
**Files**: 2 files of 1GB each (sparse files for testing)

**Expected Behavior**:
- Files hashed efficiently (streaming, not loading into memory)
- Progress updates during hash calculation
- Files moved successfully
- Memory usage remains reasonable

**Why Important**: Large files can cause memory issues if not handled properly.

---

#### **TEST_MetArt-DVD045_ManyFiles.csv** - High File Count
**Purpose**: Test performance with many small files  
**Files**: 1000 small files (1KB each)

**Expected Behavior**:
- All files processed
- Performance acceptable (< 5 minutes)
- Progress updates
- Memory usage stable

**Why Important**: Establishes performance baseline for large batches.

---

### Low Priority (Nice to Have)

#### **TEST_MetArt-DVD046_DifferentDrives.csv**
**Purpose**: Test files across different drives (C:→D:)  
**Note**: Move vs copy behavior differs across drives

#### **TEST_MetArt-DVD047_Unicode.csv**
**Purpose**: Test extreme Unicode characters (emoji, Chinese, Arabic, etc.)

#### **TEST_MetArt-DVD048_DiskSpace.csv**
**Purpose**: Test behavior when destination disk is full  
**Note**: Difficult to test automatically

#### **TEST_MetArt-DVD049_Permissions.csv**
**Purpose**: Test with insufficient write permissions  
**Note**: Requires elevated/restricted test environment

---

## Implementation Plan

### Phase 1: High Priority (Immediate)
1. Create DVD036 (brackets)
2. Create DVD038 (shared CRC)
3. Create DVD039 (CRC conflicts)
4. Create DVD040 (empty folder cleanup)

### Phase 2: Medium Priority (Next Sprint)
5. Create DVD037 (path limits)
6. Create DVD041 (malformed CSVs)
7. Create DVD042 (read-only)
8. Create DVD043 (encoding)

### Phase 3: Performance Baseline (Future)
9. Create DVD044 (large files)
10. Create DVD045 (many files)

### Phase 4: Edge Cases (As Needed)
11. Remaining scenarios based on real-world issues

---

## Test Data Structure

New test data will be added to `TestSourceData.zip`:

```
TestData/TestSourceData.zip
├── _01_CSV_Source/
│   ├── [existing CSVs]
│   ├── TEST_MetArt-DVD036_Brackets.csv
│   ├── TEST_MetArt-DVD037_PathLimit.csv
│   ├── TEST_MetArt-DVD038_SharedCRC.csv
│   ├── TEST_MetArt-DVD039_Conflicts.csv
│   ├── TEST_MetArt-DVD040_EmptyFolders.csv
│   └── [future test CSVs]
├── _02_Image_Source/
│   ├── DVD36_Brackets/
│   ├── DVD37_PathLimit/
│   ├── DVD38_Shared/
│   ├── DVD39_Conflicts/
│   └── DVD40_Empty/
└── _99_Completed/
    └── [pre-existing completed sets]
```

---

## Test Automation Updates

### Update `Test-CRCFileOrganizer.ps1`:
- Add validation for DVD036-DVD040
- Check for proper `-LiteralPath` usage (brackets test)
- Verify empty folder removal (DVD040)
- Validate shared CRC handling (DVD038)
- Check CRC mismatch detection (DVD039)

### Update `TestingData.md`:
- Document each new scenario
- Add to test matrix
- Update expected outcomes
- Add validation checklists

---

## Success Criteria

Each scenario should:
1. **Be reproducible**: Extract zip → run script → validate outcome
2. **Test one thing**: Each CSV focuses on specific edge case
3. **Have clear validation**: Pass/fail criteria documented
4. **Cover real failures**: Based on actual issues, not hypotheticals

---

## Notes

- Keep test files small (< 100KB each) for quick test runs
- Use sparse files for large file testing
- Document any manual setup steps
- Include both positive and negative test cases
- Test both -DryRun and actual execution modes
