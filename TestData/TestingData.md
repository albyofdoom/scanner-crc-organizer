# Purpose

The purpose of this folder is to provide a read-only version of test data that can be pulled from repeatedly to perform tests on the CSV/CRC processing script. They provide truncated versions of real data and include common scenarios that break scripting logic.

## Quick Reference - Expected Outcomes

| CSV File | Status | Files Move? | CSV Moves? | Special Notes |
|----------|--------|-------------|------------|---------------|
| DVD031 | ❌ Skip | No | No | Duplicate CRCs detected, entire CSV skipped |
| DVD033 | ⚠️ Incomplete | **No** (stay in source) | No | Missing 4 files, generates missing CSV |
| DVD034 | ✅ Complete | Yes → Completed | Yes → Completed | All files matched, organized by path |
| DVD035 | ⚠️ Incomplete | No | No | Zero matches, no action |
| DVD032 | ⏭️ Ignored | N/A | N/A | Pre-existing in Completed folder |
| **DVD036** | ✅ Complete | Yes → Completed | Yes → Completed | **NEW**: Brackets/braces in filenames |
| **DVD038** | ⚠️ Incomplete | No (in DVD034) | No | **NEW**: Shared CRCs with DVD034 (script limitation, expected) |
| **DVD039** | ⚠️ Incomplete | No (CRC mismatch) | No | **NEW**: Files exist but wrong CRC |
| **DVD040** | ✅ Complete | Yes → Completed | Yes → Completed | **NEW**: Empty folders cleaned up |

**Note on Hybrid Workflow**: With the new hybrid workflow, incomplete CSVs (DVD033, DVD035, DVD039) leave files in source folder untouched. Only complete CSVs (DVD034, DVD036, DVD038, DVD040) trigger file moves to the Completed folder.


## Test Scenarios Overview

Scripts should account for the following scenarios as they commonly occur in the source CSV files, as they are from legacy processes and should be used as-is to maintain proper source data integrity. 

Note: When provided, examples enclosed in parentheses are only samples and not inclusive of all test data.

**Important**: Duplicate CRCs appearing across **different CSVs** (like DVD034 and DVD038) are expected and intentional. They represent the same physical files legitimately referenced by multiple data sets in the original legacy data. The script correctly handles duplicates **within** a single CSV (which are errors), but allows duplicates **across** CSVs (which are valid). This preserves the integrity of the original legacy data structure.

### Original Test Scenarios (DVD031-035)

1. A single CSV file has duplicate CRC values corresponding to the same files with different names. 
2. A CSV file does not properly format pathname fields that contain commas. ("\vol_10025 - Alena, Elvira & Valya - Trio\")
3. Files in different folders have the same names but different dates ("logo.jpg" and "flogo.jpg")
4. Filenames contain diacritical marks. ("Ménage")
5. Filenames contain symbols commonly used in scripts ("&", "+")
6. Pathnames+Filenames when combined create full names longer than 255 characters.
7. The second CSV contains folders with CRC values from the first CSV, but named differently. Both sets should be included in the folders for each CSV when completed.
8. There is already one completed CSV set in the Completed folder that should be ignored. 
9. There are files missing from a CSV that will not match, leaving an incomplete set. 
10. All files are missing from a CSV and will have zero matches.

### NEW Test Scenarios (DVD036-040)

11. **Square brackets and curly braces in filenames** - PowerShell wildcard characters that must be handled with `-LiteralPath`
12. **Multiple CSVs reference same files** - Cross-CSV duplicate detection, files already in another CSV's completed folder
13. **CRC conflicts** - Filename exists but CRC doesn't match (wrong file content)
14. **Empty folder cleanup** - Nested folder structure should be removed after all files moved


## Test File Matrix

| CSV File | Scenarios Tested | CSV Lines | Files Available | Expected Result | Notes |
|----------|-----------------|-----------|-----------------|-----------------|-------|
| **TEST_MetArt-DVD031(Final)_42.csv** | 1 (Duplicate CRCs) | 35 (no header) | 35 files (all present) | ❌ **FAIL** - Skip processing | 7 lines are duplicates. Script should detect duplicates, log error, and skip entire CSV |
| **TEST_MetArt-DVD033(Final)_35.csv** | 2, 9 (Commas in paths, Missing files) | 35 (no header) | 31 files (4 missing) | ⚠️ **INCOMPLETE** | 7 lines have commas in Path field. Should process but remain in source. Generate missing files CSV |
| **TEST_MetArt-DVD034(Final)_35.csv** | 2-5, 7 (All special cases) | 42 (no header) | 42 files (all present) | ✅ **COMPLETE** | Commas, diacriticals ("Ménage"), symbols ("&"), shared CRCs with DVD031, long paths. Should move to Completed |
| **TEST_MetArt-DVD035(Final)_5154.csv** | 10 (No matches) | 5154 (no header) | 0 files | ⚠️ **INCOMPLETE** | Zero matches. CSV should remain in source, no moves |
| **MetArt-DVD032(Final)_5090** (in Completed) | 8 (Pre-existing) | N/A | 21 files (already complete) | ⏭️ **IGNORE** | Already in Completed folder. Should be untouched |


## Detailed CSV Specifications

### TEST_MetArt-DVD031(Final)_42.csv
- **Purpose**: Test duplicate CRC detection (Scenario 1)
- **CSV Structure**: 35 lines total
  - 7 lines contain duplicate CRC values with different filenames
  - All 35 files physically exist in `_02_Image_Source\DVD31\`
- **Expected Behavior**:
  - Script detects duplicate CRCs during CSV validation
  - Logs error message about duplicates
  - Skips processing this CSV entirely
  - CSV remains in `_01_CSV_Source\`
  - Files remain in original locations untouched
- **Test Validation**: Check log for duplicate detection message, verify CSV not processed

---

### TEST_MetArt-DVD033(Final)_35.csv
- **Purpose**: Test incomplete sets and commas in paths (Scenarios 2, 9)
- **CSV Structure**: 35 lines total
  - 7 lines have commas in the Path field (e.g., "vol_10025 - Alena, Elvira & Valya - Trio\")
  - Only 31 files exist in `_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\`
  - **Missing files**: 4 files from folders:
    - `af_11015 - Ashanti - Gioia\` (missing 2: met-art_af_11015_0003.jpg, met-art_af_11015_0004.jpg)
    - `av_11035 - Andrea - Hawaii\` (missing 2: met-art_av_11035_0001.jpg, met-art_av_11035_0002.jpg)
- **Expected Behavior**:
  - Script parses commas correctly (custom CSV parser)
  - Matches 31 files, reports 4 missing
  - CSV marked as INCOMPLETE
  - **Hybrid Workflow**: Files remain in `_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\` (not moved)
  - CSV remains in `_01_CSV_Source\`
  - Missing files CSV generated: `_98_Logs\TEST_MetArt-DVD033(Final)_35_4_missing_files.csv`
- **Test Validation**: 
  - Verify files stay in source folder
  - Check missing files CSV contains correct 4 entries
  - Confirm log shows "INCOMPLETE - files will remain in source folder"

---

### TEST_MetArt-DVD034(Final)_35.csv
- **Purpose**: Comprehensive test of edge cases (Scenarios 2-5, 7)
- **CSV Structure**: 42 lines total (no header row)
  - Commas in paths: `vol_10025 - Alena, Elvira & Valya - Trio\`
  - Diacriticals: `sg_09255 - Anna & Anna - Ménage\` (note: "é")
  - Symbols: Multiple "&" in folder names
  - Long paths: `tad_11025 - Carolina & Yalim - Atacama\` with deeply nested structure (255+ char paths)
  - Shared CRCs: `arc_10065` and `sg_09255` folders share CRCs with DVD031 but have different folder names
  - All 42 files exist in `_02_Image_Source\DVD34\`
- **Expected Behavior**:
  - Script handles all special characters correctly
  - All 42 files matched
  - CSV marked as COMPLETE
  - Files moved to `_99_Completed\TEST_MetArt-DVD034(Final)_35\` with path structure preserved
  - CSV moved to `_99_Completed\TEST_MetArt-DVD034(Final)_35\TEST_MetArt-DVD034(Final)_35.csv`
  - Folders created correctly despite commas/diacriticals/long paths
- **Test Validation**:
  - Verify all 42 files in Completed folder
  - Check path structure preserved (especially commas: "vol_10025 - Alena\" folder exists)
  - Confirm diacriticals preserved ("Ménage")
  - Verify long nested paths handled correctly

---

### TEST_MetArt-DVD035(Final)_5154.csv
- **Purpose**: Test zero matches scenario (Scenario 10)
- **CSV Structure**: Contains references to files from original DVD035 set
  - No matching files exist in `_02_Image_Source\`
- **Expected Behavior**:
  - Script finds zero matching files
  - CSV marked as INCOMPLETE (0 matches)
  - **Hybrid Workflow**: CSV remains in `_01_CSV_Source\`
  - No file moves attempted
  - Log shows zero matches
- **Test Validation**: 
  - CSV remains in source folder
  - Log shows "Found 0 files in source"
  - No destination folders created

---

### MetArt-DVD032(Final)_5090 (Pre-existing in Completed)
- **Purpose**: Test pre-existing completed sets are ignored (Scenario 8)
- **Structure**: Already complete set in `_99_Completed\`
  - 21 files across 3 folders
  - CSV file included in the folder
- **Expected Behavior**:
  - Script ignores this folder entirely (not a CSV in source)
  - All files and folders remain untouched
  - No log entries about this set
- **Test Validation**: Compare before/after state - should be identical


## New Test Scenarios (High Priority Edge Cases)

### TEST_MetArt-DVD036_Brackets.csv
- **Purpose**: Test PowerShell wildcard characters in filenames (brackets, braces)
- **File Count**: 10 files (no header row)
- **Structure**: Files in `_02_Image_Source\DVD36_Brackets\`
  - Files with `[square brackets]` in names
  - Files with `{curly braces}` in names
  - Mixed bracket types in single filename
  - Normal baseline files for comparison
- **CSV Details**: 
  - All files in root path (`\,`)
  - Tests `-LiteralPath` handling
- **Expected Behavior**:
  - All 10 files matched correctly (brackets don't trigger wildcard expansion)
  - CSV marked as COMPLETE
  - Files moved to `_99_Completed\TEST_MetArt-DVD036_Brackets\`
  - CSV moved to completed folder
  - Source folder `DVD36_Brackets\` removed (empty)
- **Test Validation**:
  - Verify all 10 files in completed folder
  - Confirm filenames with brackets unchanged
  - Check source folder removed
  - Verify CSV in completed folder

### TEST_MetArt-DVD038_SharedCRC.csv
- **Purpose**: Test multiple CSVs referencing same file CRCs
- **File Count**: 10 entries (no header row)
- **Structure**: References same CRCs as DVD034 files
  - Different filenames but identical CRC values
  - Different subfolder paths
  - Tests cross-CSV duplicate detection
- **CSV Details**:
  - No actual files in source (files already moved by DVD034)
  - CRCs match files in DVD034's completed folder
- **Expected Behavior**:
  - Script detects files already in `TEST_MetArt-DVD034(Final)_35` completed folder
  - Marks all files as "found in completed folder"
  - CSV marked as COMPLETE (all files accounted for)
  - CSV moved to `_99_Completed\TEST_MetArt-DVD038_SharedCRC\`
  - No file duplication (files stay in DVD034's folder)
- **Test Validation**:
  - Verify CSV moved to completed folder
  - Confirm no duplicate files created
  - Check log shows files found in DVD034
  - Files remain only in DVD034's folder

### TEST_MetArt-DVD039_Conflicts.csv
- **Purpose**: Test CRC mismatch detection (filename exists but wrong content)
- **File Count**: 4 entries (no header row)
- **Structure**: Files in `_02_Image_Source\DVD39_Conflicts\`
  - 3 files with intentionally wrong CRC values in CSV
  - 1 file with correct CRC value
- **CSV Details**:
  - First 3 entries: CSV expects CRC `AAAAAAAA`, `BBBBBBBB`, `CCCCCCCC`
  - Actual files have different CRCs
  - Last entry: matches correctly
- **Expected Behavior**:
  - Script detects CRC mismatches for 3 files
  - Logs show "CRC mismatch" for conflicting files
  - Only 1 file matches correctly
  - CSV marked as INCOMPLETE (only 1/4 files found)
  - CSV stays in `_01_CSV_Source\`
  - All files stay in `_02_Image_Source\DVD39_Conflicts\`
  - Missing files CSV generated listing 3 unmatched entries
- **Test Validation**:
  - Verify CSV remains in source folder
  - Confirm all 4 files still in source
  - Check log for CRC mismatch messages
  - Verify missing CSV generated with 3 entries

### TEST_MetArt-DVD040_EmptyFolders.csv
- **Purpose**: Test empty folder cleanup after complete set moves
- **File Count**: 4 files (no header row)
- **Structure**: Nested folder hierarchy
  - `_02_Image_Source\DVD40_EmptyFolders\Level1\Level2\Level3\` (2 files)
  - `_02_Image_Source\DVD40_EmptyFolders\AlsoEmpty\Subfolder\` (1 file)
  - `_02_Image_Source\DVD40_EmptyFolders\` (1 file in root)
- **CSV Details**:
  - Files span multiple nested folders
  - All files should match
  - Tests empty folder removal after moves
- **Expected Behavior**:
  - All 4 files matched and moved
  - CSV marked as COMPLETE
  - Files moved to `_99_Completed\TEST_MetArt-DVD040_EmptyFolders\` (with subfolder structure)
  - CSV moved to completed folder
  - All empty source folders removed: `DVD40_EmptyFolders\`, `Level1\`, `Level2\`, `Level3\`, `AlsoEmpty\`, `Subfolder\`
- **Test Validation**:
  - Verify all 4 files in completed folder with proper subfolder structure
  - Confirm entire `DVD40_EmptyFolders\` tree removed from source
  - Check log shows folder cleanup
  - Verify CSV in completed folder

  
## Expected State on start

**Note**: These paths are relative to `TestData\TestWorking\` after extracting `TestSourceData.zip`

.\TestWorking\_01_CSV_Source\
.\TestWorking\_02_Image_Source\
.\TestWorking\_98_Logs\
.\TestWorking\_99_Completed\
.\TestWorking\_02_Image_Source\DVD31\
.\TestWorking\_02_Image_Source\DVD34\
.\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\
.\TestWorking\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\arc_10065 - Joulie - Apollus\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\sg_09255 - Anna & Anna - Menage\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11165 - Julia - Chapeau\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11195 - Presenting Adriana\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\tad_11025 - Carolina & Yalim - Atacama\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\vol_10025 - Alena, Elvira & Valya - Trio\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina, Yalim - Atacama\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina, Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina, Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\TEST_met-art_tad_11025_0004.jpg\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina, Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\TEST_met-art_tad_11025_0005.jpg\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\
.\CRC-FileOrganizer\TestSourceData\TestingData.md
.\CRC-FileOrganizer\TestSourceData\_01_CSV_Source\TEST_MetArt-DVD031(Final)_42.csv
.\CRC-FileOrganizer\TestSourceData\_01_CSV_Source\TEST_MetArt-DVD033(Final)_35.csv
.\CRC-FileOrganizer\TestSourceData\_01_CSV_Source\TEST_MetArt-DVD034(Final)_35.csv
.\CRC-FileOrganizer\TestSourceData\_01_CSV_Source\TEST_MetArt-DVD035(Final)_5154.csv
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_met-art_alan_09295_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_met-art_alan_09295_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_met-art_alan_09295_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_met-art_alan_09295_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_met-art_alan_09295_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_met-art_alan_09295_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_met-art_alan_09295_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_met-art_alan_09295_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_met-art_alan_09295_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_met-art_alan_09295_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\arc_10065 - Joulie - Apollus\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\arc_10065 - Joulie - Apollus\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\arc_10065 - Joulie - Apollus\TEST_met-art_arc_10065_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\arc_10065 - Joulie - Apollus\TEST_met-art_arc_10065_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\arc_10065 - Joulie - Apollus\TEST_met-art_arc_10065_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\arc_10065 - Joulie - Apollus\TEST_met-art_arc_10065_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\arc_10065 - Joulie - Apollus\TEST_met-art_arc_10065_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_met-art_as_09245_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_met-art_as_09245_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_met-art_as_09245_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_met-art_as_09245_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_met-art_as_09245_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\sg_09255 - Anna & Anna - Menage\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\sg_09255 - Anna & Anna - Menage\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\sg_09255 - Anna & Anna - Menage\TEST_met-art_sg_09255_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\sg_09255 - Anna & Anna - Menage\TEST_met-art_sg_09255_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\sg_09255 - Anna & Anna - Menage\TEST_met-art_sg_09255_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\sg_09255 - Anna & Anna - Menage\TEST_met-art_sg_09255_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD31\sg_09255 - Anna & Anna - Menage\TEST_met-art_sg_09255_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11165 - Julia - Chapeau\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11165 - Julia - Chapeau\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11165 - Julia - Chapeau\TEST_met-art_as_11165_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11165 - Julia - Chapeau\TEST_met-art_as_11165_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11165 - Julia - Chapeau\TEST_met-art_as_11165_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11165 - Julia - Chapeau\TEST_met-art_as_11165_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11165 - Julia - Chapeau\TEST_met-art_as_11165_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11195 - Presenting Adriana\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11195 - Presenting Adriana\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11195 - Presenting Adriana\TEST_met-art_as_11195_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11195 - Presenting Adriana\TEST_met-art_as_11195_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11195 - Presenting Adriana\TEST_met-art_as_11195_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11195 - Presenting Adriana\TEST_met-art_as_11195_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\as_11195 - Presenting Adriana\TEST_met-art_as_11195_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\TEST_met-art_tad_11025_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\TEST_met-art_tad_11025_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\tad_11025 - Carolina & Yalim - Atacama\tad_11025 - Carolina & Yalim - Atacama\TEST_met-art_tad_11025_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\vol_10025 - Alena, Elvira & Valya - Trio\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\vol_10025 - Alena, Elvira & Valya - Trio\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\vol_10025 - Alena, Elvira & Valya - Trio\TEST_met-art_vol_10025_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\vol_10025 - Alena, Elvira & Valya - Trio\TEST_met-art_vol_10025_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\vol_10025 - Alena, Elvira & Valya - Trio\TEST_met-art_vol_10025_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\vol_10025 - Alena, Elvira & Valya - Trio\TEST_met-art_vol_10025_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\DVD34\vol_10025 - Alena, Elvira & Valya - Trio\TEST_met-art_vol_10025_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\met-art_af_11015_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\met-art_af_11015_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\met-art_af_11015_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\met-art_arc_10265_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\met-art_arc_10265_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\met-art_arc_10265_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\met-art_arc_10265_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\met-art_arc_10265_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\met-art_av_11035_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\met-art_av_11035_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\met-art_av_11035_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\met-art_cep_10305_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\met-art_cep_10305_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\met-art_cep_10305_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\met-art_cep_10305_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\met-art_cep_10305_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\logo.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\met-art_yo_11045_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\met-art_yo_11045_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\met-art_yo_11045_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\met-art_yo_11045_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\met-art_yo_11045_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\TEST_MetArt-DVD032(Final)_5090.csv
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_met-art_as_10115_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_met-art_as_10115_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_met-art_as_10115_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_met-art_as_10115_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_met-art_as_10115_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_met-art_av_10135_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_met-art_av_10135_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_met-art_av_10135_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_met-art_av_10135_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_met-art_av_10135_0005.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_flogo.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_logo.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_met-art_jb_10085_0001.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_met-art_jb_10085_0002.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_met-art_jb_10085_0003.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_met-art_jb_10085_0004.jpg
.\CRC-FileOrganizer\TestSourceData\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_met-art_jb_10085_0005.jpg

## Expected state on end

**Note**: These paths show the expected state after test completion in `TestData\TestWorking\`

.\TestWorking\_01_CSV_Source\
.\TestWorking\_01_CSV_Source\TEST_MetArt-DVD031(Final)_42.csv
.\TestWorking\_01_CSV_Source\TEST_MetArt-DVD033(Final)_35.csv
.\TestWorking\_01_CSV_Source\TEST_MetArt-DVD035(Final)_5154.csv
.\TestWorking\_02_Image_Source\
.\TestWorking\_02_Image_Source\DVD31\
.\TestWorking\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\
.\TestWorking\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_logo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_met-art_alan_09295_0001.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_met-art_alan_09295_0002.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_met-art_alan_09295_0003.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_met-art_alan_09295_0004.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09259 - Inna - Rejuva\TEST2_met-art_alan_09295_0005.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_logo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_met-art_alan_09295_0001.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_met-art_alan_09295_0002.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_met-art_alan_09295_0003.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_met-art_alan_09295_0004.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\alan_09295 - Inna - Rejuva\TEST_met-art_alan_09295_0005.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_logo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_met-art_as_09245_0001.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_met-art_as_09245_0002.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_met-art_as_09245_0003.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_met-art_as_09245_0004.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD31\as_09245 - Renee - Undressing\TEST_met-art_as_09245_0005.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_logo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0001.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0002.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0003.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0004.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0005.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_logo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0001.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0002.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0003.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0004.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\DVD34\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0005.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\flogo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\logo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\met-art_af_11015_0001.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\met-art_af_11015_0002.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\af_11015 - Ashanti - Gioia\met-art_af_11015_0005.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\flogo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\logo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\met-art_arc_10265_0001.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\met-art_arc_10265_0002.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\met-art_arc_10265_0003.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\met-art_arc_10265_0004.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\arc_10265 - Joulie - Tresor\met-art_arc_10265_0005.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\flogo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\logo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\met-art_av_11035_0003.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\met-art_av_11035_0004.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\av_11035 - Andrea - Hawaii\met-art_av_11035_0005.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\flogo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\logo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\met-art_cep_10305_0001.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\met-art_cep_10305_0002.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\met-art_cep_10305_0003.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\met-art_cep_10305_0004.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\cep_10305 - Presenting Lilu\met-art_cep_10305_0005.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\flogo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\logo.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\met-art_yo_11045_0001.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\met-art_yo_11045_0002.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\met-art_yo_11045_0003.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\met-art_yo_11045_0004.jpg
.\CRC-FileOrganizer\TestWorking\_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\yo_11045 - Misato - Levante\met-art_yo_11045_0005.jpg
.\CRC-FileOrganizer\TestWorking\_98_Logs\
.\CRC-FileOrganizer\TestWorking\_98_Logs\TEST_MetArt-DVD033(Final)_35_4_missing_files.csv
.\CRC-FileOrganizer\TestWorking\_98_Logs\file_moves_20251112_121152.log
.\CRC-FileOrganizer\TestWorking\_99_Completed\
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\TEST_MetArt-DVD032(Final)_5090.csv
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_logo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_met-art_as_10115_0001.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_met-art_as_10115_0002.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_met-art_as_10115_0003.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_met-art_as_10115_0004.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\as_10115 - Irina - Rubicus\TEST_met-art_as_10115_0005.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_logo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_met-art_av_10135_0001.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_met-art_av_10135_0002.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_met-art_av_10135_0003.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_met-art_av_10135_0004.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\av_10135 - Liza & Jenya aka Katie Fey - Orion\TEST_met-art_av_10135_0005.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_logo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_met-art_jb_10085_0001.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_met-art_jb_10085_0002.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_met-art_jb_10085_0003.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_met-art_jb_10085_0004.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\MetArt-DVD032(Final)_5090\jb_10085 - Jacqueline - Abacus\TEST_met-art_jb_10085_0005.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD033(Final)_35\
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\TEST_MetArt-DVD034(Final)_35.csv
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\arc_10065 - Joulie - Set 3\
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\arc_10065 - Joulie - Set 3\TEST_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\arc_10065 - Joulie - Set 3\TEST_logo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0001.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0002.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0003.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0004.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\arc_10065 - Joulie - Set 3\TEST_met-art_JoulArc_10065_0005.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11165 - Julia - Chapeau\
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11165 - Julia - Chapeau\TEST_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11165 - Julia - Chapeau\TEST_logo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11165 - Julia - Chapeau\TEST_met-art_as_11165_0001.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11165 - Julia - Chapeau\TEST_met-art_as_11165_0002.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11165 - Julia - Chapeau\TEST_met-art_as_11165_0003.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11165 - Julia - Chapeau\TEST_met-art_as_11165_0004.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11165 - Julia - Chapeau\TEST_met-art_as_11165_0005.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11195 - Presenting Adriana\
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11195 - Presenting Adriana\TEST_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11195 - Presenting Adriana\TEST_logo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11195 - Presenting Adriana\TEST_met-art_as_11195_0001.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11195 - Presenting Adriana\TEST_met-art_as_11195_0002.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11195 - Presenting Adriana\TEST_met-art_as_11195_0003.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11195 - Presenting Adriana\TEST_met-art_as_11195_0004.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\as_11195 - Presenting Adriana\TEST_met-art_as_11195_0005.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\sg_09255 - Anna & Anna - Ménage\
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\sg_09255 - Anna & Anna - Ménage\TEST_flogo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\sg_09255 - Anna & Anna - Ménage\TEST_logo.jpg
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\tad_11025 - Carolina & Yalim - Atacama\
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\tad_11025 - Carolina\
.\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\vol_10025 - Alena\
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0001.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0002.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0003.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0004.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\sg_09255 - Anna & Anna - Ménage\TEST_met-art_sg_09255_0005.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\tad_11025 - Carolina & Yalim - Atacama\TEST_flogo.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\tad_11025 - Carolina & Yalim - Atacama\TEST_logo.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\tad_11025 - Carolina\TEST_met-art_tad_11025_0001.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\tad_11025 - Carolina\TEST_met-art_tad_11025_0002.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\tad_11025 - Carolina\TEST_met-art_tad_11025_0003.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\tad_11025 - Carolina\TEST_met-art_tad_11025_0004.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\tad_11025 - Carolina\TEST_met-art_tad_11025_0005.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\vol_10025 - Alena\TEST_flogo.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\vol_10025 - Alena\TEST_logo.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\vol_10025 - Alena\TEST_met-art_vol_10025_0001.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\vol_10025 - Alena\TEST_met-art_vol_10025_0002.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\vol_10025 - Alena\TEST_met-art_vol_10025_0003.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\vol_10025 - Alena\TEST_met-art_vol_10025_0004.jpg
D:\ScanSorting\_90_TestBed\CRC-FileOrganizer\TestWorking\_99_Completed\TEST_MetArt-DVD034(Final)_35\vol_10025 - Alena\TEST_met-art_vol_10025_0005.jpg


## Test Execution Checklist

Use this checklist when running tests to ensure all scenarios are validated:

### Pre-Test Setup
- [ ] Extract `TestSourceData.zip` to working directory
- [ ] Verify folder structure matches "Expected State on start"
- [ ] Clear any existing log files in `_98_Logs\`
- [ ] Verify script parameters point to test folders

### Test Execution
- [ ] Run script with test parameters
- [ ] Monitor console output for errors
- [ ] Check log file is created in `_98_Logs\`

### Post-Test Validation

#### TEST_MetArt-DVD031(Final)_42.csv (Duplicate CRCs)
- [ ] CSV remains in `_01_CSV_Source\`
- [ ] Log shows duplicate CRC detection message
- [ ] No folders created in Completed
- [ ] All 35 files remain in `_02_Image_Source\DVD31\` (untouched)

#### TEST_MetArt-DVD033(Final)_35.csv (Incomplete - Missing Files)
- [ ] CSV remains in `_01_CSV_Source\`
- [ ] Log shows "INCOMPLETE - files will remain in source folder"
- [ ] Log shows "Found 31 files in source, 0 already in completed folder, 4 missing"
- [ ] Missing files CSV created: `_98_Logs\TEST_MetArt-DVD033(Final)_35_4_missing_files.csv`
- [ ] Missing CSV contains exactly 4 entries (af_11015 x2, av_11035 x2)
- [ ] All 31 files remain in `_02_Image_Source\TEST_MetArt-DVD033(Final)_5923\` (not moved)

#### TEST_MetArt-DVD034(Final)_35.csv (Complete - All Edge Cases)
- [ ] CSV moved to `_99_Completed\TEST_MetArt-DVD034(Final)_35\`
- [ ] Log shows "COMPLETE - will move to completed folder"
- [ ] All 42 files moved to `_99_Completed\TEST_MetArt-DVD034(Final)_35\`
- [ ] Folder structure preserved correctly:
  - [ ] `arc_10065 - Joulie - Set 3\` (7 files)
  - [ ] `as_11165 - Julia - Chapeau\` (7 files)
  - [ ] `as_11195 - Presenting Adriana\` (7 files)
  - [ ] `sg_09255 - Anna & Anna - Ménage\` (7 files) - verify "é" preserved
  - [ ] `vol_10025 - Alena\` (7 files) - verify comma in path handled
  - [ ] `tad_11025 - Carolina & Yalim - Atacama\` (2 files: logo, flogo)
  - [ ] `tad_11025 - Carolina\` (5 files) - verify long nested path handled
- [ ] Source folders `_02_Image_Source\DVD34\` now empty (or minimal)

#### TEST_MetArt-DVD035(Final)_5154.csv (Incomplete - Zero Matches)
- [ ] CSV remains in `_01_CSV_Source\`
- [ ] Log shows "Found 0 files in source"
- [ ] No folders created in Completed
- [ ] No file moves attempted

#### MetArt-DVD032(Final)_5090 (Pre-existing Completed)
- [ ] Folder remains in `_99_Completed\MetArt-DVD032(Final)_5090\`
- [ ] All 21 files unchanged
- [ ] No log entries about this set

#### TEST_MetArt-DVD036_Brackets.csv (Special Characters - NEW)
- [ ] CSV moved to `_99_Completed\TEST_MetArt-DVD036_Brackets\`
- [ ] All 10 files moved to completed folder
- [ ] Filenames with brackets preserved: `[2024] Preview.jpg`, `Title[Final].jpg`, etc.
- [ ] Source folder `DVD36_Brackets\` removed (empty)
- [ ] Log shows all files matched correctly

#### TEST_MetArt-DVD038_SharedCRC.csv (Shared CRCs - NEW)
- [ ] CSV moved to `_99_Completed\TEST_MetArt-DVD038_SharedCRC\`
- [ ] No duplicate files created
- [ ] Log shows files found in DVD034's completed folder
- [ ] Files remain only in DVD034's folder structure
- [ ] CSV marked as COMPLETE despite no file moves

#### TEST_MetArt-DVD039_Conflicts.csv (CRC Mismatches - NEW)
- [ ] CSV remains in `_01_CSV_Source\`
- [ ] All 4 files remain in `_02_Image_Source\DVD39_Conflicts\`
- [ ] Log shows "CRC mismatch" for 3 files
- [ ] Missing files CSV generated with 3 entries
- [ ] Only 1 file matched (TEST_correct_file.jpg)

#### TEST_MetArt-DVD040_EmptyFolders.csv (Folder Cleanup - NEW)
- [ ] CSV moved to `_99_Completed\TEST_MetArt-DVD040_EmptyFolders\`
- [ ] All 4 files moved with proper subfolder structure
- [ ] Entire `DVD40_EmptyFolders\` tree removed from source
- [ ] Log shows folder cleanup operations
- [ ] No empty folders left in `_02_Image_Source\`

### Performance Validation (Hybrid Workflow)
- [ ] Script start time faster than old workflow (no staging migration)
- [ ] No staging folder references in log
- [ ] Incomplete CSVs show "files will remain in source folder" message

### File Count Summary
After successful test run, you should have:
- **In `_01_CSV_Source\`**: 4 CSVs (DVD031, DVD033, DVD035, DVD039)
- **In `_02_Image_Source\`**: Files from DVD031 (35), DVD033 (31), DVD039 (4), others empty/removed
- **In `_99_Completed\`**: 5 folders
  - `MetArt-DVD032(Final)_5090\` (21 files + CSV) - pre-existing
  - `TEST_MetArt-DVD034(Final)_35\` (42 files + CSV) - newly moved
  - `TEST_MetArt-DVD036_Brackets\` (10 files + CSV) - **NEW**
  - `TEST_MetArt-DVD038_SharedCRC\` (CSV only, no files) - **NEW**
  - `TEST_MetArt-DVD040_EmptyFolders\` (4 files + CSV) - **NEW**
- **In `_98_Logs\`**: 1 log file + 2 missing files CSVs (DVD033, DVD039)

### Common Issues to Watch For
- **Commas in paths**: Ensure `vol_10025 - Alena, Elvira & Valya - Trio\` is parsed correctly
- **Diacriticals**: Verify "Ménage" folder name preserved
- **Long paths**: Check deeply nested `tad_11025` structure doesn't fail
- **Duplicate detection**: DVD031 should be caught before any processing starts
- **Hybrid workflow**: Incomplete CSVs should NOT move files
- **Brackets in filenames**: Ensure `[2024]` and `{braces}` don't trigger wildcard expansion - **NEW**
- **Shared CRCs**: DVD038 should detect files in DVD034 without duplication - **NEW**
- **CRC mismatches**: DVD039 should log conflicts, not move wrong files - **NEW**
- **Empty folder cleanup**: DVD040 source folders completely removed after move - **NEW**
