<!-- Copilot / Agent instructions for scanner-crc-organizer -->
# scanner-crc-organizer — AI Agent Instructions

This file gives focused, actionable guidance so an AI coding agent can be immediately productive in this repository.

**Big Picture:**
- **Purpose:** Organize downloaded image sets by matching CRC32 hashes from CSV metadata to files in a source folder and move complete sets to `CompletedFolder`.
- **Primary languages/tools:** PowerShell (primary orchestration), Python (CSV utilities & CRC reporting), no external binaries.

**Key files:**
- `CRC-FileOrganizer.ps1`: Main orchestrator — read CSVs, build CRC:Size lookup, match entries, move files, and log results.
- `CRC-FileOrganizerLib.ps1`: Shared helpers — `Add-CRC32Type`, `Get-CRC32Hash`, `Get-CandidateMap`, and simulation helpers.
- `CSV-Validate-Repair.py`: Python utility for repairing CSVs and preserving comments/encoding.
- `CRC32_Folder_Calc.py`: Python CRC32 folder scanner (compatible CSV schema for this tool).
- `README.md`: Contains usage, parameters, and important conventions (CSV schema, default folders, DryRun behavior).

**Important patterns & conventions (do not change lightly):**
- **Matching strategy:** Uses a composite key `CRC:Size` for O(1) lookups — many functions and tests assume that key format exactly.
- **CSV schema:** Expected 4–5 columns (FileName, Size, CRC32, Path, Comment). CSVs often have no header; scripts detect and skip a header row if present.
- **CRC implementation:** `Add-CRC32Type` injects a CRC32 .NET type; `Get-CRC32Hash` returns an 8-char uppercase hex string. PowerShell runspaces import the function definitions rather than compiling duplicate types.
- **Parallelism:** `ForEach-Object -Parallel` with `-ThrottleLimit` is used for hashing. Agents editing parallel code should preserve the runspace function-injection pattern used in `CRC-FileOrganizer.ps1` (the script captures function bodies and reassigns them inside the parallel block).
- **Dry-run semantics:** `-DryRun` switch prevents creation of folders and file moves; logs are still written. Respect dry-run code paths when adding features.
- **ForceCSV behavior:** `-ForceCSV` accepts base names or wildcard patterns; `-ForceCSVMoveEmpty` allows moving CSVs even when zero matches were found. Tests and logs depend on these behaviors.

**Developer workflows / commands**
- Run PowerShell CSV/organizer tests: `.\tests\run-crc-tests.ps1` (or `.\tests\Quick-Test-CRC.ps1` for a fast run).
- Run Python tests: `pytest tests/` (Python 3.9+; optional venv in `venv_readme.md`).
- Dry-run example: `.\CRC-FileOrganizer.ps1 -DryRun -ThrottleLimit 8`.
- Repair CSV: `python CSV-Validate-Repair.py broken.csv`.

**What to look for when editing code:**
- Preserve the `CRC:Size` key everywhere. Renaming this format requires updating `Get-CandidateMap`, matching logic in `CRC-FileOrganizer.ps1`, and tests in `tests/`.
- If changing CRC implementation, ensure `Get-CRC32Hash` still returns uppercase 8-hex strings; tests expect this format.
- When modifying parallel hashing, keep the pattern of capturing function definitions (`${function:Get-CRC32Hash}.ToString()`) and reassigning inside runspaces to avoid Add-Type duplication and serialization issues.
- Maintain the RFC4180-compatible CSV parsing approach used in scripts (there are custom parsers in both PS scripts and library functions).

**Where tests assert behavior (examples):**
- `tests/test_crc32_folder_calc.py` — assumes `CRC32_Folder_Calc.py` outputs headers `FileName,Size,CRC32,Path` and uppercase 8-character CRCs.
- PowerShell tests in `tests/*.ps1` validate matching, duplicate CRC handling, force-move semantics, and log outputs. Use those tests to validate changes to CSV or moving logic.

**Common gotchas for automated edits:**
- Do not remove or change the log-archiving step — many workflows depend on archived logs in `_98_Logs/Archive`.
- CSV encoding: scripts expect UTF-8 (tools perform BOM detection in `Get-Encoding`). If you change encoding handling, update callers and tests.
- Path normalization: scripts convert forward slashes to backslashes and normalize `Path` column values — maintain that normalization.

If anything in this file is unclear or you'd like more details (for example, a quick reference to the matching code paths or tests to run after edits), tell me which area to expand and I'll update this file.

**Legacy patterns & migration notes**
- `Add-EscChars` vs `-LiteralPath`: older scripts include `Add-EscChars` to escape wildcards — prefer `-LiteralPath` for new work, but do not remove legacy helpers without running tests.
- 7-Zip usage is present in older scripts (`C:\Program Files\7-Zip\7z.exe`) — migration notes suggest `Compress-Archive` / `Expand-Archive` as native alternatives; update carefully and run tests.

**Environment & tests (practical commands)**
- Recommended Python: 3.9+ (project tests run under pytest). Use a venv at repo root: `python -m venv .venv` then `.\.venv\Scripts\Activate.ps1` and `pip install -r requirements.txt`.
- PowerShell test runner: `pwsh -NoProfile -File .\tests\run-crc-tests.ps1` or `.	ests\Quick-Test-CRC.ps1` for a fast smoke test.
- Python tests: `pytest tests/` (already used in CI locally — expect fast feedback).

**Do not edit / safety**
- Do not modify signature blocks (the `# SIG # Begin signature block` section) — these are auto-generated and must not be edited manually.
- Preserve the log-archiving step (`_98_Logs/Archive`) and Dry-run semantics — automated workflows and tests rely on archived logs and dry-run behavior.

**Runspace / parallelism example**
- When using `ForEach-Object -Parallel`, the script captures function definitions as strings and reassigns them inside the runspace to avoid duplicate `Add-Type` compilations. Example pattern in `CRC-FileOrganizer.ps1`:

	- `$GetCRC32HashFunction = ${function:Get-CRC32Hash}.ToString()`
	- In the parallel block: `${function:Get-CRC32Hash} = $using:GetCRC32HashFunction; Add-CRC32Type; $hash = Get-CRC32Hash -FilePath $_.FullName`

These lines are intentionally fragile; preserve the pattern when refactoring parallel hashing.

If you'd like, I can merge more specific snippets from the old instructions (examples for `Add-EscChars` usage or `ps_syntax_check.ps1` invocation). Approve and I'll apply them.

**Variable Naming**
- **Goal:** Use descriptive, context-specific names to avoid shadowing and improve readability across scripts and runspaces.
- **PowerShell pattern:** prefer `$sourceFiles`, `$destinationFiles`, `$fileToMove` rather than repeated `$files`/`$file` in nested scopes.
- **Parallel/runspace caution:** avoid reusing short names (e.g., `$i`, `$file`) when values are captured by runspaces; prefer `$crcFile`, `$csvEntryIndex`, `$candidateFile`.
- **Arrays vs single items:** name collections plural (`$candidateMap`, `$matchedFiles`) and single items singular (`$matchedFile`).
- **Example (good):**
	- `$fileList = Get-ChildItem -LiteralPath $SourceFolderCRC`
	- `foreach ($candidateFile in $candidateMap[$key]) { ... }`
- **Example (bad):**
	- `foreach ($file in $files) { foreach ($file in $other) { ... } }`  — avoid reuse of `$file`.
