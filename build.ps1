<#
  RedRock IT — static site builder
  --------------------------------
  Assembles the deployable .html files in the repo root from:
     _src/partials/head.html   shared <head>, utility bar, header, mobile drawer
     _src/partials/foot.html   shared footer, sticky call bar, back-to-top
     _src/partials/*.html      reusable blocks, pulled in with <!--INCLUDE:name-->
     _src/pages/<name>.html    per-page <main> content + a META block
                               (JSON-LD lives inline at the foot of each page)

  Also regenerates sitemap.xml from the page list.

  Usage:  pwsh -File build.ps1
#>

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$src   = Join-Path $root '_src'
$parts = Join-Path $src 'partials'
$pages = Join-Path $src 'pages'

$BASE = 'https://redrockit.com/'

# Content hashes for cache busting. Browsers cache assets/css/site.css for as long
# as GitHub's headers allow, so a change would not reach returning visitors until
# that expired. Putting the hash in the URL makes every change a new URL.
function Get-AssetVersion($relPath) {
    $full = Join-Path $root $relPath
    if (-not (Test-Path $full)) { return '0' }
    (Get-FileHash $full -Algorithm MD5).Hash.Substring(0, 8).ToLower()
}
$cssV = Get-AssetVersion 'assets/css/site.css'
$jsV  = Get-AssetVersion 'assets/js/site.js'

$head = Get-Content (Join-Path $parts 'head.html') -Raw
$foot = Get-Content (Join-Path $parts 'foot.html') -Raw

# Pages that should not appear in the sitemap.
$noIndex = @('404.html')

$built = @()

foreach ($file in Get-ChildItem (Join-Path $pages '*.html') | Sort-Object Name) {
    $name = $file.Name
    $raw  = Get-Content $file.FullName -Raw

    # ---- parse the META block ----
    $m = [regex]::Match($raw, '(?s)^\s*<!--META(.*?)-->')
    if (-not $m.Success) { throw "$name is missing its <!--META ... --> block" }

    $meta = @{}
    foreach ($line in $m.Groups[1].Value -split "`n") {
        $kv = [regex]::Match($line, '^\s*([a-zA-Z]+)\s*:\s*(.+?)\s*$')
        if ($kv.Success) { $meta[$kv.Groups[1].Value.ToLower()] = $kv.Groups[2].Value }
    }
    foreach ($required in @('title', 'desc')) {
        if (-not $meta.ContainsKey($required)) { throw "$name META is missing '$required'" }
    }

    $body = $raw.Substring($m.Length)

    # ---- expand <!--INCLUDE:xxx--> ----
    $body = [regex]::Replace($body, '<!--INCLUDE:([a-z0-9\-]+)-->', {
        param($mm)
        $inc = Join-Path $parts ($mm.Groups[1].Value + '.html')
        if (-not (Test-Path $inc)) { throw "Unknown include '$($mm.Groups[1].Value)'" }
        Get-Content $inc -Raw
    })

    # ---- canonical: index.html canonicalises to the bare domain ----
    $canon = if ($name -eq 'index.html') { '' } else { $name }

    # ---- assemble ----
    $h = $head
    $h = $h.Replace('{{TITLE}}',     [System.Net.WebUtility]::HtmlEncode($meta.title))
    $h = $h.Replace('{{DESC}}',      [System.Net.WebUtility]::HtmlEncode($meta.desc))
    $h = $h.Replace('{{CANONICAL}}', $canon)
    $h = $h.Replace('{{ROBOTS}}',     $(if ($meta.ContainsKey('robots')) { $meta.robots } else { 'index,follow,max-image-preview:large' }))
    $h = $h.Replace('{{HEAD_EXTRA}}', $(if ($meta.ContainsKey('head'))   { $meta.head }   else { '' }))
    $h = $h.Replace('assets/css/site.css', "assets/css/site.css?v=$cssV")
    $h = $h.Replace('assets/js/site.js',   "assets/js/site.js?v=$jsV")

    # mark the active top-level nav item
    if ($meta.ContainsKey('nav') -and $meta.nav) {
        $h = $h -replace ('(data-nav="' + [regex]::Escape($meta.nav) + '")'), '$1 aria-current="page"'
    }

    $out = $h + $body.TrimEnd() + "`n" + $foot

    # strip leftover placeholders so nothing ships half-substituted
    if ($out -match '\{\{[A-Z_]+\}\}') {
        throw "$name still contains an unsubstituted placeholder: $($Matches[0])"
    }

    $dest = Join-Path $root $name
    [System.IO.File]::WriteAllText($dest, $out, (New-Object System.Text.UTF8Encoding $false))

    $kb = [math]::Round(([System.Text.Encoding]::UTF8.GetByteCount($out)) / 1kb, 1)
    '{0,-42} {1,7} KB' -f $name, $kb

    if ($noIndex -notcontains $name) {
        $built += [pscustomobject]@{
            Loc      = $BASE + $canon
            Priority = $(if ($name -eq 'index.html') { '1.0' }
                         elseif ($name -match '^(services|industries|contact|pricing)\.html$') { '0.9' }
                         else { '0.8' })
        }
    }
}

# ---- sitemap ----
$today = Get-Date -Format 'yyyy-MM-dd'
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
[void]$sb.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
foreach ($u in $built | Sort-Object -Property @{E={[double]$_.Priority}; Descending=$true}, Loc) {
    [void]$sb.AppendLine('  <url>')
    [void]$sb.AppendLine('    <loc>' + $u.Loc + '</loc>')
    [void]$sb.AppendLine('    <lastmod>' + $today + '</lastmod>')
    [void]$sb.AppendLine('    <priority>' + $u.Priority + '</priority>')
    [void]$sb.AppendLine('  </url>')
}
[void]$sb.AppendLine('</urlset>')
[System.IO.File]::WriteAllText((Join-Path $root 'sitemap.xml'), $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))

''
"Built $($built.Count + $noIndex.Count) pages. sitemap.xml lists $($built.Count) URLs."
"Asset versions: css=$cssV js=$jsV"
