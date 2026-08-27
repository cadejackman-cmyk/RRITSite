<#
  RedRock IT - static site builder
  --------------------------------
  Assembles the deployable .html files in the repo root from:
     _src/partials/head.html   shared <head>, utility bar, header, mobile drawer
     _src/partials/foot.html   shared footer, sticky call bar, back-to-top
     _src/partials/*.html      reusable blocks, pulled in with <!--INCLUDE:name-->
     _src/pages/<name>.html    per-page <main> content + a META block
                               (JSON-LD lives inline at the foot of each page)
     _src/pages/blog/*.html    blog section, built out to /blog/<name>.html

  Blog pages differ from the main pages in three ways:
    - they live one directory deep, so every relative link inherited from the
      shared partials is rewritten to root-relative on the way out
    - their BlogPosting and BreadcrumbList JSON-LD is generated from the META
      block rather than hand-written, so a post cannot ship with stale markup
    - they are listed in their own sitemap-blog.xml, not in sitemap.xml, and
      their lastmod is the post's real updated date rather than today

  Also regenerates sitemap.xml and sitemap-blog.xml from the page list.

  Usage:  pwsh -File build.ps1
#>

$ErrorActionPreference = 'Stop'
$root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$src   = Join-Path $root '_src'
$parts = Join-Path $src 'partials'
$pages = Join-Path $src 'pages'

$BASE = 'https://redrockit.com/'

# Content hashes for cache busting. Browsers cache assets/css/site.css for as long
# as the origin's headers allow, so a change would not reach returning visitors
# until that expired. Putting the hash in the URL makes every change a new URL.
function Get-AssetVersion($relPath) {
    $full = Join-Path $root $relPath
    if (-not (Test-Path $full)) { return '0' }
    (Get-FileHash $full -Algorithm MD5).Hash.Substring(0, 8).ToLower()
}
$cssV = Get-AssetVersion 'assets/css/site.css'
$jsV  = Get-AssetVersion 'assets/js/site.js'

$head = Get-Content (Join-Path $parts 'head.html') -Raw
$foot = Get-Content (Join-Path $parts 'foot.html') -Raw

# Pages that should not appear in any sitemap.
$noIndex = @('404.html')

function Enc($s) { [System.Net.WebUtility]::HtmlEncode($s) }

# JSON string escaping for the generated blog JSON-LD.
function Jsn($s) {
    $s = $s -replace '\\', '\\\\'
    $s = $s -replace '"', '\"'
    $s -replace '\r?\n', ' '
}

# The shared partials link relatively (href="contact.html", src="assets/..."),
# which is correct at the site root and wrong one directory down. Rather than
# keep a second copy of the header and footer for /blog/, rewrite the finished
# page: anything not already absolute, protocol-relative, root-relative or a
# bare fragment gets a leading slash.
function ConvertTo-RootRelative([string]$html) {
    $html = [regex]::Replace($html, '(href|src)="(?![a-zA-Z][a-zA-Z0-9+.-]*:)(?!//)(?![/#])([^"]*)"', '$1="/$2"')
    # The home page canonicalises to the bare domain, so link it that way rather
    # than pointing the whole blog section at a second URL for the same page.
    $html -replace 'href="/index\.html((?:#|\?)[^"]*)?"', 'href="/$1"'
}

# ---- collect page sources: root pages first, then the blog section -----------
$srcPages = @()
foreach ($f in Get-ChildItem (Join-Path $pages '*.html') | Sort-Object Name) {
    $srcPages += [pscustomobject]@{ Full = $f.FullName; Name = $f.Name; Rel = $f.Name; Section = '' }
}
$blogSrc = Join-Path $pages 'blog'
if (Test-Path $blogSrc) {
    foreach ($f in Get-ChildItem (Join-Path $blogSrc '*.html') | Sort-Object Name) {
        $srcPages += [pscustomobject]@{ Full = $f.FullName; Name = $f.Name; Rel = 'blog/' + $f.Name; Section = 'blog' }
    }
}

# ---- parse every META block up front ----------------------------------------
# The blog index needs each post's metadata before any page is assembled, so
# parsing happens in its own pass rather than inside the build loop.
foreach ($p in $srcPages) {
    $raw = Get-Content $p.Full -Raw

    $m = [regex]::Match($raw, '(?s)^\s*<!--META(.*?)-->')
    if (-not $m.Success) { throw "$($p.Rel) is missing its <!--META ... --> block" }

    $meta = @{}
    foreach ($line in $m.Groups[1].Value -split "`n") {
        $kv = [regex]::Match($line, '^\s*([a-zA-Z0-9]+)\s*:\s*(.+?)\s*$')
        if ($kv.Success) { $meta[$kv.Groups[1].Value.ToLower()] = $kv.Groups[2].Value }
    }

    $required = @('title', 'desc')
    if ($p.Section -eq 'blog' -and $p.Name -ne 'index.html') {
        # A post missing these would build a sitemap entry and JSON-LD that lie.
        $required += @('date', 'excerpt', 'category')
    }
    foreach ($key in $required) {
        if (-not $meta.ContainsKey($key)) { throw "$($p.Rel) META is missing '$key'" }
    }
    if ($meta.ContainsKey('date') -and $meta.date -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw "$($p.Rel) META date must be yyyy-mm-dd, got '$($meta.date)'"
    }

    $p | Add-Member -NotePropertyName Meta -NotePropertyValue $meta
    $p | Add-Member -NotePropertyName Body -NotePropertyValue $raw.Substring($m.Length)
}

# ---- newest-first post list, shared by the blog index and sitemap-blog.xml ----
$posts = @($srcPages |
    Where-Object { $_.Section -eq 'blog' -and $_.Name -ne 'index.html' -and $noIndex -notcontains $_.Name } |
    Sort-Object -Property @{ Expression = { $_.Meta.date }; Descending = $true }, Name)

# ---- the card grid injected into /blog/ in place of <!--POSTLIST--> ----------
$listSb = New-Object System.Text.StringBuilder
[void]$listSb.AppendLine('<div class="grid g-3">')
foreach ($p in $posts) {
    $url     = '/blog/' + $p.Name
    $shown   = [datetime]::ParseExact($p.Meta.date, 'yyyy-MM-dd', $null).ToString('MMMM d, yyyy')
    $heading = if ($p.Meta.ContainsKey('h1')) { $p.Meta.h1 } else { ($p.Meta.title -split '\|')[0].Trim() }
    $read    = if ($p.Meta.ContainsKey('read')) { ' &middot; ' + (Enc $p.Meta.read) + ' min read' } else { '' }

    [void]$listSb.AppendLine('  <article class="card">')
    [void]$listSb.AppendLine('    <a class="card-link" href="' + $url + '">')
    # .card-link is a column flex container, so a bare inline-flex pill would
    # stretch to the full card width. The paragraph wrapper keeps it shrink-wrapped.
    [void]$listSb.AppendLine('      <p class="u-mb-sm"><span class="pill pill-brand">' + (Enc $p.Meta.category) + '</span></p>')
    [void]$listSb.AppendLine('      <h3>' + (Enc $heading) + '</h3>')
    [void]$listSb.AppendLine('      <p>' + (Enc $p.Meta.excerpt) + '</p>')
    [void]$listSb.AppendLine('      <p class="note-sm u-mt-sm"><time datetime="' + $p.Meta.date + '">' + $shown + '</time>' + $read + '</p>')
    [void]$listSb.AppendLine('    </a>')
    [void]$listSb.AppendLine('  </article>')
}
[void]$listSb.AppendLine('</div>')
$postList = $listSb.ToString()

# ---- build --------------------------------------------------------------------
$mainUrls = @()
$blogUrls = @()

foreach ($p in $srcPages) {
    $meta   = $p.Meta
    $body   = $p.Body
    $isBlog = $p.Section -eq 'blog'
    $isPost = $isBlog -and $p.Name -ne 'index.html'

    # ---- expand <!--INCLUDE:xxx--> ----
    $body = [regex]::Replace($body, '<!--INCLUDE:([a-z0-9\-]+)-->', {
        param($mm)
        $inc = Join-Path $parts ($mm.Groups[1].Value + '.html')
        if (-not (Test-Path $inc)) { throw "Unknown include '$($mm.Groups[1].Value)'" }
        Get-Content $inc -Raw
    })

    # ---- the blog index gets its card grid generated from the posts ----
    if ($isBlog -and $p.Name -eq 'index.html') {
        if ($body -notmatch '<!--POSTLIST-->') { throw 'blog/index.html is missing its <!--POSTLIST--> marker' }
        $body = $body.Replace('<!--POSTLIST-->', $postList)
    }

    # ---- canonical: index.html to the bare domain, the blog index to /blog/ ----
    $canon = if ($p.Name -eq 'index.html') { if ($isBlog) { 'blog/' } else { '' } } else { $p.Rel }

    # ---- assemble ----
    $h = $head
    $h = $h.Replace('{{TITLE}}',      (Enc $meta.title))
    $h = $h.Replace('{{DESC}}',       (Enc $meta.desc))
    $h = $h.Replace('{{CANONICAL}}',  $canon)
    $h = $h.Replace('{{OGTYPE}}',     $(if ($isPost) { 'article' } else { 'website' }))
    $h = $h.Replace('{{ROBOTS}}',     $(if ($meta.ContainsKey('robots')) { $meta.robots } else { 'index,follow,max-image-preview:large' }))
    $h = $h.Replace('{{HEAD_EXTRA}}', $(if ($meta.ContainsKey('head'))   { $meta.head }   else { '' }))
    $h = $h.Replace('assets/css/site.css', "assets/css/site.css?v=$cssV")
    $h = $h.Replace('assets/js/site.js',   "assets/js/site.js?v=$jsV")

    # mark the active top-level nav item
    if ($meta.ContainsKey('nav') -and $meta.nav) {
        $h = $h -replace ('(data-nav="' + [regex]::Escape($meta.nav) + '")'), '$1 aria-current="page"'
    }

    # ---- posts get their structured data generated from META ----
    $extra = ''
    if ($isPost) {
        $heading = if ($meta.ContainsKey('h1')) { $meta.h1 } else { ($meta.title -split '\|')[0].Trim() }
        $updated = if ($meta.ContainsKey('updated')) { $meta.updated } else { $meta.date }
        $img     = if ($meta.ContainsKey('image')) { $BASE + $meta.image } else { $BASE + 'assets/img/og.jpg' }
        $extra = @"

<script type="application/ld+json">
{
  "@context":"https://schema.org",
  "@graph":[
    {
      "@type":"BlogPosting",
      "headline":"$(Jsn $heading)",
      "description":"$(Jsn $meta.excerpt)",
      "articleSection":"$(Jsn $meta.category)",
      "datePublished":"$($meta.date)",
      "dateModified":"$updated",
      "inLanguage":"en-US",
      "image":"$img",
      "mainEntityOfPage":{"@type":"WebPage","@id":"$BASE$($p.Rel)"},
      "url":"$BASE$($p.Rel)",
      "author":{"@type":"Organization","name":"RedRock IT","url":"$BASE"},
      "publisher":{
        "@type":"Organization",
        "name":"RedRock IT",
        "url":"$BASE",
        "logo":{"@type":"ImageObject","url":"$($BASE)assets/img/mark.png"}
      }
    },
    {
      "@type":"BreadcrumbList",
      "itemListElement":[
        {"@type":"ListItem","position":1,"name":"Home","item":"$BASE"},
        {"@type":"ListItem","position":2,"name":"Blog","item":"$($BASE)blog/"},
        {"@type":"ListItem","position":3,"name":"$(Jsn $heading)","item":"$BASE$($p.Rel)"}
      ]
    }
  ]
}
</script>
"@
    }

    $out = $h + $body.TrimEnd() + $extra + "`n" + $foot

    # ---- links that must not be relative --------------------------------
    # Blog pages sit one directory down. The 404 page is worse: nginx serves it
    # at whatever URI the visitor asked for, so a relative asset link resolves
    # against that path and breaks on anything except a single root-level
    # segment (/nope works, /nope/ and /blog/nope do not). Root-relative is the
    # only form that renders correctly from every depth.
    if ($isBlog -or $p.Name -eq '404.html') { $out = ConvertTo-RootRelative $out }

    # strip leftover placeholders so nothing ships half-substituted
    if ($out -match '\{\{[A-Z_]+\}\}') {
        throw "$($p.Rel) still contains an unsubstituted placeholder: $($Matches[0])"
    }

    $dest    = Join-Path $root $p.Rel
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
    [System.IO.File]::WriteAllText($dest, $out, (New-Object System.Text.UTF8Encoding $false))

    $kb = [math]::Round(([System.Text.Encoding]::UTF8.GetByteCount($out)) / 1kb, 1)
    '{0,-46} {1,7} KB' -f $p.Rel, $kb

    if ($noIndex -contains $p.Name) { continue }

    if ($isBlog) {
        $blogUrls += [pscustomobject]@{
            Loc     = $BASE + $canon
            LastMod = $(if ($isPost) {
                            if ($meta.ContainsKey('updated')) { $meta.updated } else { $meta.date }
                        } elseif ($posts.Count) {
                            $newest = $posts | Select-Object -First 1
                            if ($newest.Meta.ContainsKey('updated')) { $newest.Meta.updated } else { $newest.Meta.date }
                        } else {
                            Get-Date -Format 'yyyy-MM-dd'
                        })
            Priority = $(if ($isPost) { '0.7' } else { '0.8' })
        }
    } else {
        $mainUrls += [pscustomobject]@{
            Loc      = $BASE + $canon
            LastMod  = Get-Date -Format 'yyyy-MM-dd'
            Priority = $(if ($p.Name -eq 'index.html') { '1.0' }
                         elseif ($p.Name -match '^(services|industries|contact|pricing)\.html$') { '0.9' }
                         else { '0.8' })
        }
    }
}

# ---- sitemaps ------------------------------------------------------------------
# The blog lives in its own sitemap so its crawl and indexing can be read
# separately from the money pages in Search Console. Both are listed in robots.txt.
function Write-Sitemap($urls, $file) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">')
    foreach ($u in $urls | Sort-Object -Property @{ E = { [double]$_.Priority }; Descending = $true }, Loc) {
        [void]$sb.AppendLine('  <url>')
        [void]$sb.AppendLine('    <loc>' + $u.Loc + '</loc>')
        [void]$sb.AppendLine('    <lastmod>' + $u.LastMod + '</lastmod>')
        [void]$sb.AppendLine('    <priority>' + $u.Priority + '</priority>')
        [void]$sb.AppendLine('  </url>')
    }
    [void]$sb.AppendLine('</urlset>')
    [System.IO.File]::WriteAllText((Join-Path $root $file), $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
}

Write-Sitemap $mainUrls 'sitemap.xml'
Write-Sitemap $blogUrls 'sitemap-blog.xml'

''
"Built $($srcPages.Count) pages, $($posts.Count) of them blog posts."
"sitemap.xml lists $($mainUrls.Count) URLs. sitemap-blog.xml lists $($blogUrls.Count) URLs."
"Asset versions: css=$cssV js=$jsV"
