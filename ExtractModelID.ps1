param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$TargetDirectory = "J:\Dropbox\PowerShell-Scripts\Samples\ExtractModelID",
        
        [Parameter(Mandatory = $false, Position = 1)]
        [string]$OutputFileName = "ExtractedModelData.csv"
)

Function Get-ModelDataFromHtml
{
param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path
)
if (-not (Test-Path $Path)) {
        Throw "File not found: $Path"
}

# read HTML
$html = Get-Content -Path $Path -Raw -ErrorAction Stop

# First, try to extract model data from discussion titles (forum listing pages)
# Pattern: "Model Name / ICGID: XX-XXXXX / #12345"
$discussionMatches = [regex]::Matches($html, '<a\s+href="([^"]*discussion/\d+/[^"]*)"[^>]*>([^<]+?)\s*/\s*ICGID:\s*([A-Z]{2}-[A-Z0-9]+)\s*/\s*#(\d+)</a>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
if ($discussionMatches.Count -gt 0) {
        foreach ($dm in $discussionMatches) {
                $modelName = $dm.Groups[2].Value.Trim()
                $icgid = $dm.Groups[3].Value.Trim()
                $modelNumber = $dm.Groups[4].Value.Trim()
                $discussionUrl = $dm.Groups[1].Value
                
                # Construct model page URL: https://www.thenude.eu/ModelName_ModelNumber.htm
                # Replace spaces with underscores in model name
                $urlModelName = $modelName -replace '\s+','_'
                $modelPageUrl = "https://www.thenude.eu/${urlModelName}_${modelNumber}.htm"
                
                [PSCustomObject]@{
                        ModelName = $modelName
                        ICGID = $icgid
                        ModelNumber = $modelNumber
                        ModelPageUrl = $modelPageUrl
                        DiscussionUrl = $discussionUrl
                        ParsingMethod = 'forumListing'
                }
        }
        return
}

# If no discussion listings found, try to extract site links from model pages
# Quick regex-first pass: if we can extract titles by regex, prefer that (avoids COM issues)
$quickDivMatches = [regex]::Matches($html, '<div[^>]*class\s*=\s*"title"[^>]*>(.*?)</div>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
if ($quickDivMatches.Count -gt 0) {
        foreach ($dm in $quickDivMatches) {
                $divHtml = $dm.Groups[1].Value
                $aMatches = [regex]::Matches($divHtml, '<a[^>]*href\s*=\s*"([^"]+)"[^>]*>(.*?)</a>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
                foreach ($am in $aMatches) {
                        $linkText = ([regex]::Replace($am.Groups[2].Value,'^\s+|\s+$',''))
                        # Extract site name (the main text), aliases from parentheses, and model name
                        $siteName = ''
                        $aliases = ''
                        $modelName = $linkText
                        
                        if ($linkText -match '\(([^)]+)\)') {
                                $aliases = $matches[1]
                                $linkText = ($linkText -replace '\s*\([^)]+\)\s*','').Trim()
                        }
                        # The site name is the cleaned link text (after removing aliases)
                        $siteName = $linkText
                        
                        [PSCustomObject]@{
                                SiteName = $siteName
                                Aliases = $aliases
                                Href = $am.Groups[1].Value
                                ParsingMethod = 'regexQuick'
                        }
                }
        }
        return
}

# Parse HTML using the Windows HTML COM parser
# We'll record which parsing method succeeded so the CSV can include it
$parsingMethod = 'unknown'
try {
                $doc = New-Object -ComObject "HTMLFile"
                $doc.open()
                # Prefer setting innerHTML when Body is available (avoids dispatch issues)
                $hasBody = $false
                try { if ($null -ne $doc.Body) { $hasBody = $true } } catch { $hasBody = $false }
                if ($hasBody) {
                        try {
                                $doc.Body.innerHTML = $html
                                $parsingMethod = 'innerHTML'
                        }
                        catch {
                                # If innerHTML fails, fall back to reflection write
                                Write-Warning "doc.Body.innerHTML failed: $($_.Exception.Message)"
                                $doc.GetType().InvokeMember('write',[System.Reflection.BindingFlags]::InvokeMethod,$null,$doc, @($html))
                                $parsingMethod = 'write'
                        }
                }
                else {
                        # Fall back to reflection write to avoid PowerShell COM dispatch type mismatch
                        $doc.GetType().InvokeMember('write',[System.Reflection.BindingFlags]::InvokeMethod,$null,$doc, @($html))
                        $parsingMethod = 'write'
                }
                $doc.close()
}
catch {
        Write-Warning "document.write() failed: $($_.Exception.Message)"
        # If a document object exists and has a body, try setting innerHTML
                # Safely check for Body property without invoking COM members directly in an expression
                $hasBody = $false
                if ($doc) {
                        try { if ($null -ne $doc.Body) { $hasBody = $true } } catch { $hasBody = $false }
                }
                if ($hasBody) {
                        try {
                                $doc.Body.innerHTML = $html
                                $parsingMethod = 'innerHTML'
                        }
                        catch {
                                Write-Warning "body.innerHTML also failed: $($_.Exception.Message)"
                                $parsingMethod = 'unknown'
                        }
                }
        else {
                # Fallback: create an InternetExplorer.Application and set body.innerHTML (safer than write)
                $ie = $null
                try {
                        $ie = New-Object -ComObject "InternetExplorer.Application"
                        $ie.Navigate("about:blank")
                        while ($ie.Busy -or $ie.ReadyState -ne 4) { Start-Sleep -Milliseconds 50 }
                        $iedoc = $ie.Document
                        # Prefer setting innerHTML; if Body is not available, fall back to reflection write
                        $hasBody = $false
                        try { if ($null -ne $iedoc.Body) { $hasBody = $true } } catch { $hasBody = $false }
                        if ($hasBody) {
                                try {
                                        $iedoc.Body.innerHTML = $html
                                        $doc = $iedoc
                                        $parsingMethod = 'IEFallback'
                                }
                                catch {
                                        Write-Warning "IE body.innerHTML failed: $($_.Exception.Message)"
                                        # try reflection write as last resort
                                        try {
                                                $iedoc.GetType().InvokeMember('write',[System.Reflection.BindingFlags]::InvokeMethod,$null,$iedoc, @($html))
                                                $doc = $iedoc
                                                $parsingMethod = 'IEFallback'
                                        }
                                        catch {
                                                Write-Warning "IE reflection write failed: $($_.Exception.Message)"
                                                $parsingMethod = 'unknown'
                                        }
                                }
                        }
                        else {
                                try {
                                        $iedoc.GetType().InvokeMember('write',[System.Reflection.BindingFlags]::InvokeMethod,$null,$iedoc, @($html))
                                        $doc = $iedoc
                                        $parsingMethod = 'IEFallback'
                                }
                                catch {
                                        Write-Warning "IE reflection write failed: $($_.Exception.Message)"
                                        $parsingMethod = 'unknown'
                                }
                        }
                }
                catch {
                        Write-Warning "COM HTML parsing failed (IE fallback): $($_.Exception.Message)"
                        $parsingMethod = 'unknown'
                }
                finally {
                        if ($ie) {
                                try { $ie.Quit() } catch { }
                        }
                }
        }
}

# If COM parsing failed, fall back to a simple regex-based parser
if (($parsingMethod -eq 'unknown') -or -not $doc) {
                $divMatches = [regex]::Matches($html, '<div[^>]*class\s*=\s*"title"[^>]*>(.*?)</div>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        foreach ($dm in $divMatches) {
                $divHtml = $dm.Groups[1].Value
                $aMatches = [regex]::Matches($divHtml, '<a[^>]*href\s*=\s*"([^"]+)"[^>]*>(.*?)</a>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
                foreach ($am in $aMatches) {
                        $linkText = ([regex]::Replace($am.Groups[2].Value,'^\s+|\s+$',''))
                        # Extract site name (the main text), aliases from parentheses, and model name
                        $siteName = ''
                        $aliases = ''
                        $modelName = $linkText
                        
                        if ($linkText -match '\(([^)]+)\)') {
                                $aliases = $matches[1]
                                $linkText = ($linkText -replace '\s*\([^)]+\)\s*','').Trim()
                        }
                        # The site name is the cleaned link text (after removing aliases)
                        $siteName = $linkText
                        
                        [PSCustomObject]@{
                                SiteName = $siteName
                                Aliases = $aliases
                                Href = $am.Groups[1].Value
                                ParsingMethod = 'regexFallback'
                        }
                }
        }
        return
}

# Find divs with class "title" and enumerate <a> children
$divs = @()
$allDivs = @($doc.getElementsByTagName('div'))
foreach ($d in $allDivs) {
        try {
                if ($d.className -eq 'title') { $divs += $d }
        }
        catch { continue }
}

foreach ($div in $divs) {
        foreach ($a in @($div.getElementsByTagName('a'))) {
                $linkText = ($a.innerText -replace '^\s+|\s+$','')
                # Extract site name (the main text), aliases from parentheses
                $siteName = ''
                $aliases = ''
                
                if ($linkText -match '\(([^)]+)\)') {
                        $aliases = $matches[1]
                        $linkText = ($linkText -replace '\s*\([^)]+\)\s*','').Trim()
                }
                # The site name is the cleaned link text (after removing aliases)
                $siteName = $linkText
                
                [PSCustomObject]@{
                        SiteName = $siteName
                        Aliases = $aliases
                        Href = $a.href
                        ParsingMethod = $parsingMethod
                }
        }
}
}


#if ($MyInvocation.InvocationName -ne '.') {
        # Set location variables
        $scriptDir = $TargetDirectory
        
        # Validate directory exists
        if (-not (Test-Path $scriptDir)) {
                Write-Error "Target directory does not exist: $scriptDir"
                exit 1
        }
        
        Set-Location $scriptDir

        # process folder of HTML files
        $ModelArray = @()
        Get-ChildItem -Path $scriptDir -Filter *.html | ForEach-Object {
                $htmlFilePath = $_.FullName
                Write-Host "Processing file: $htmlFilePath"

                $ModelArray += Get-ModelDataFromHtml -Path $htmlFilePath
        }

        # Export with stable column order
        $outPath = Join-Path $scriptDir $OutputFileName
        
        # Check if we have forum listing data or site link data
        if ($ModelArray.Count -gt 0 -and $ModelArray[0].PSObject.Properties.Name -contains 'ModelName') {
                # Forum listing format
                $ModelArray | Select-Object ModelName,ICGID,ModelNumber,ModelPageUrl,DiscussionUrl,ParsingMethod | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8
        } else {
                # Site link format
                $ModelArray | Select-Object SiteName,Aliases,Href,ParsingMethod | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8
        }
        Write-Host "Extracted data has been saved to $outPath"
#}
