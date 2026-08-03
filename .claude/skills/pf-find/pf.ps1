# pf.ps1 -- symbol navigation for the pfsuite AutoLISP tree.
# Answers "where is X / what calls X / show me X" WITHOUT reading whole .lsp files.
#
# Execution policy blocks running .ps1 files on locked-down machines, so this is
# loaded by content, not by path:
#   Invoke-Expression (Get-Content -Raw .claude\skills\pf-find\pf.ps1); pf find pfa:xr
#
# PowerShell 5.1 compatible. No ternary, no ??, no external binaries.

# No Set-StrictMode / Set-Location / $ErrorActionPreference here: this file is
# evaluated in the caller's session, so anything set at top level leaks into it.

# ---------------------------------------------------------------- paths ----
# $PSScriptRoot is empty when this file is Invoke-Expression'd, so the tree is
# located by walking up from the working directory instead.
function Get-PfRoot {
  $d = (Get-Location).Path
  while ($d) {
    if (Test-Path (Join-Path $d 'pfsuite\pftools-load.lsp')) { return $d }
    $p = Split-Path $d -Parent
    if ($p -eq $d) { break }
    $d = $p
  }
  throw "pf: cannot find the V5 root (no pfsuite\pftools-load.lsp above $((Get-Location).Path))"
}

$script:PfRoot = Get-PfRoot
$script:PfSrc  = Join-Path $script:PfRoot 'pfsuite'
$script:PfIdxD = Join-Path $script:PfRoot '.claude\pf-index'
$script:PfIdx  = Join-Path $script:PfIdxD 'symbols.tsv'

# Sort_Object is culture-aware and ignores punctuation, so "pfp-proof.lsp" and
# "pfpalette.lsp" come out in the opposite order from a byte comparison. Every
# path ordering here is ordinal so it matches the tree walk it replaced.
function Sort-PfPath { param([object[]]$Items)
  # @($null) is a 1-element array holding null, not an empty array -- an empty
  # result must stay empty or callers see one phantom item.
  $a = @()
  if ($null -ne $Items) { $a = @($Items | Where-Object { $null -ne $_ }) }
  if ($a.Count -lt 2) { return $a }
  $cmp = [System.Comparison[object]]{
    param($x, $y)
    return [string]::CompareOrdinal($x.FullName, $y.FullName)
  }
  [System.Array]::Sort($a, $cmp)
  return $a
}

function Get-PfLspFiles {
  Sort-PfPath (Get-ChildItem -Path $script:PfSrc -Filter *.lsp -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\Opendcl_Reference\\' -and
                   $_.FullName -notmatch '\\_attic\\' })
}

function Get-PfRel { param([string]$Full)
  $p = $script:PfSrc + '\'
  if ($Full.StartsWith($p)) { return $Full.Substring($p.Length).Replace('\','/') }
  return $Full.Replace('\','/')
}

function Write-PfLines { param([string[]]$Lines, [string]$Path)
  $enc = New-Object System.Text.UTF8Encoding $false     # no BOM, LF endings
  $text = ''
  if ($Lines.Count -gt 0) { $text = ($Lines -join "`n") + "`n" }
  [System.IO.File]::WriteAllText($Path, $text, $enc)
}

# GNU `sort -f`: fold case, then break ties by a full byte comparison.
function Sort-PfFold { param([string[]]$Lines)
  # Must stay [string[]]: Where-Object yields object[], which will not bind to
  # the Comparison[string] delegate below.
  $a = [string[]]@()
  if ($null -ne $Lines) { $a = [string[]]@($Lines | Where-Object { $null -ne $_ }) }
  if ($a.Count -lt 2) { return $a }
  $cmp = [System.Comparison[string]]{
    param($x, $y)
    $r = [string]::Compare($x, $y, [System.StringComparison]::OrdinalIgnoreCase)
    if ($r -ne 0) { return $r }
    return [string]::CompareOrdinal($x, $y)
  }
  [System.Array]::Sort($a, $cmp)
  return $a
}

# ---------------------------------------------------------------- index ----
# A doc block is the run of ";;" lines directly above the defun. Prefer its
# signature line ";; (name args) -> result"; else its first line.
function Build-PfIndex {
  if (-not (Test-Path $script:PfIdxD)) { New-Item -ItemType Directory -Force $script:PfIdxD | Out-Null }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($f in Get-PfLspFiles) {
    $rel = Get-PfRel $f.FullName
    $sig = ''; $first = ''
    $n = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
      $n++
      if ($line -match '^;;[^;]' -or $line -eq ';;') {
        $t = $line -replace '^;+[ \t]*', ''
        if ($t -ne '') {
          if ($sig -eq '' -and $t.StartsWith('(')) { $sig = $t }
          if ($first -eq '') { $first = $t }
        }
        continue
      }
      if ($line -match '^\(defun') {
        $name = $line -replace '^\(defun[ \t]+', ''
        $name = $name -replace '[ \t()].*$', ''
        $d = $first
        if ($sig -ne '') { $d = $sig }
        $out.Add(("{0}`t{1}`t{2}`t{3}" -f $name, $rel, $n, $d))
        $sig = ''; $first = ''
        continue
      }
      $sig = ''; $first = ''
    }
  }
  # Write a temp file and move it into place: a build that dies partway must
  # not leave a truncated or unsorted index behind for the next `find` to read.
  $sorted = Sort-PfFold $out.ToArray()
  $tmp = $script:PfIdx + '.tmp'
  Write-PfLines $sorted $tmp
  Move-Item -LiteralPath $tmp -Destination $script:PfIdx -Force
  "indexed {0} symbols -> .claude/pf-index/symbols.tsv" -f $sorted.Count
}

function Confirm-PfIndex {
  if (-not (Test-Path $script:PfIdx)) { Build-PfIndex | Write-Host; return }
  $idxTime = (Get-Item $script:PfIdx).LastWriteTimeUtc
  foreach ($f in Get-PfLspFiles) {
    if ($f.LastWriteTimeUtc -gt $idxTime) { Build-PfIndex | Write-Host; return }
  }
}

function Read-PfIndex {
  if (-not (Test-Path $script:PfIdx)) { return @() }
  [System.IO.File]::ReadAllLines($script:PfIdx) | Where-Object { $_ -ne '' } | ForEach-Object {
    $p = $_.Split("`t")
    $doc = ''
    if ($p.Count -ge 4) { $doc = $p[3] }
    New-Object PSObject -Property @{ Name = $p[0]; Rel = $p[1]; Line = [int]$p[2]; Doc = $doc }
  }
}

# Print the doc block + paren-balanced body of the defun at FILE:LINE.
function Show-PfDefun { param([string]$Path, [int]$Start)
  $lines = [System.IO.File]::ReadAllLines($Path)
  $buf = New-Object System.Collections.Generic.List[string]
  $from = $Start - 12
  if ($from -lt 1) { $from = 1 }
  for ($i = $from; $i -lt $Start; $i++) {
    $l = $lines[$i - 1]
    if ($l -like ';; *') { $buf.Add($l) } else { $buf.Clear() }
  }
  foreach ($l in $buf) { $l }

  $depth = 0; $instr = $false
  for ($i = $Start; $i -le $lines.Count; $i++) {
    $l = $lines[$i - 1]
    $ch = $l.ToCharArray()
    $done = $false
    for ($j = 0; $j -lt $ch.Length; $j++) {
      $c = $ch[$j]
      if ($instr) {
        if ($c -eq '\') { $j++ } elseif ($c -eq '"') { $instr = $false }
        continue
      }
      if ($c -eq '"') { $instr = $true; continue }
      if ($c -eq ';') { break }
      if ($c -eq '(') { $depth++ }
      elseif ($c -eq ')') { $depth--; if ($depth -eq 0) { $done = $true; break } }
    }
    $l
    if ($done) { return }
  }
}

# Content search across the tree, honouring the same exclusions.
function Search-PfTree { param([string]$Pattern, [string[]]$Extensions)
  $re = New-Object System.Text.RegularExpressions.Regex $Pattern
  $files = Sort-PfPath (Get-ChildItem -Path $script:PfSrc -Recurse -File |
    Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() -and
                   $_.FullName -notmatch '\\Opendcl_Reference\\' -and
                   $_.FullName -notmatch '\\_attic\\' })
  foreach ($f in $files) {
    $rel = Get-PfRel $f.FullName
    $n = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
      $n++
      if ($re.IsMatch($line)) { "{0}:{1}:{2}" -f $rel, $n, $line }
    }
  }
}

function Show-PfUsage {
@'
pf <cmd> -- pfsuite symbol navigation (run from the V5 working dir)

  find <regex>      symbols whose name matches -> name  file:line  one-line doc
  show <symbol>     the doc comment + full body of that defun (exact name)
  refs <symbol>     every call site, definition excluded  (file:line: text)
  api <module>      the "Public API" section of that module's README.md
  outline <module>  SECTION banners with the defuns under each
  modules           module list, load order, line counts
  grep <regex>      content search across .lsp only, with file:line
  index             force a rebuild of the symbol index

module = folder name (pfanchor, pflabel, pftools-lib, ...)
'@
}

# ------------------------------------------------------------- dispatch ----
function pf {
  [CmdletBinding()]
  param(
    [string]$Cmd = 'help',
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
  )
  $a = @($Rest)

  switch ($Cmd) {

    'index' { Build-PfIndex; return }

    'find' {
      if ($a.Count -lt 1) { Write-Error 'usage: pf find <regex>'; return }
      Confirm-PfIndex
      $re = New-Object System.Text.RegularExpressions.Regex $a[0], 'IgnoreCase'
      foreach ($e in Read-PfIndex) {
        if ($re.IsMatch($e.Name)) {
          "{0,-28} {1}:{2}" -f $e.Name, $e.Rel, $e.Line
          if ($e.Doc -ne '') { "{0,-28}   {1}" -f '', $e.Doc }
        }
      }
      return
    }

    'show' {
      if ($a.Count -lt 1) { Write-Error 'usage: pf show <symbol>'; return }
      Confirm-PfIndex
      $found = $false
      foreach ($e in Read-PfIndex) {
        if ($e.Name -cne $a[0]) { continue }
        $found = $true
        "===== {0}  ({1}:{2}) =====" -f $e.Name, $e.Rel, $e.Line
        Show-PfDefun (Join-Path $script:PfSrc ($e.Rel -replace '/','\')) $e.Line
        ''
      }
      if (-not $found) { Write-Error "no defun named '$($a[0])' -- try: pf find $($a[0])" }
      return
    }

    'refs' {
      if ($a.Count -lt 1) { Write-Error 'usage: pf refs <symbol>'; return }
      $e = [System.Text.RegularExpressions.Regex]::Escape($a[0])
      $pat = '(^|[^A-Za-z0-9:_>-])' + $e + '([^A-Za-z0-9:_>-]|$)'
      $defRe = New-Object System.Text.RegularExpressions.Regex ('\(defun[ \t]*' + $e)
      Search-PfTree $pat @('.lsp', '.dcl', '.md') |
        Where-Object { -not $defRe.IsMatch($_) }
      return
    }

    'api' {
      if ($a.Count -lt 1) { Write-Error 'usage: pf api <module>'; return }
      $f = Join-Path $script:PfSrc ("{0}\README.md" -f $a[0])
      if (-not (Test-Path $f)) { Write-Error "no README at pfsuite/$($a[0])/README.md"; return }
      $on = $false
      foreach ($line in [System.IO.File]::ReadAllLines($f)) {
        if ($line -match '^## Public API') { $on = $true }
        elseif ($on -and $line -match '^## ') { break }
        if ($on) { $line }
      }
      return
    }

    'outline' {
      if ($a.Count -lt 1) { Write-Error 'usage: pf outline <module>'; return }
      $m = $a[0]
      $f = Join-Path $script:PfSrc ("{0}\{1}.lsp" -f $m, $m)   # the namesake wins
      if (-not (Test-Path $f)) {
        $c = Get-PfLspFiles | Where-Object { $_.FullName -match ('\\' + [regex]::Escape($m) + '\\') } | Select-Object -First 1
        if (-not $c) { Write-Error "no .lsp under pfsuite/$m/"; return }
        $f = $c.FullName
      }
      "# {0}" -f (Get-PfRel $f)
      $n = 0
      foreach ($line in [System.IO.File]::ReadAllLines($f)) {
        $n++
        if ($line -match '^;;; SECTION') {
          $s = $line -replace '^;;;[ \t]*', ''
          ''
          "{0,5}  {1}" -f $n, $s
        }
        elseif ($line -match '^\(defun') {
          $name = $line -replace '^\(defun[ \t]+', ''
          $name = $name -replace '[ \t()].*$', ''
          "{0,5}      {1}" -f $n, $name
        }
      }
      return
    }

    'modules' {
      $load = Join-Path $script:PfSrc 'pftools-load.lsp'
      $i = 0
      foreach ($line in [System.IO.File]::ReadAllLines($load)) {
        if ($line -notmatch '\(load \(strcat \*pftools-dir\*') { continue }
        $parts = $line.Split('"')
        if ($parts.Count -lt 2) { continue }
        $relp = $parts[1]
        $i++
        $full = Join-Path $script:PfSrc ($relp -replace '/','\')
        $count = 0
        if (Test-Path $full) { $count = [System.IO.File]::ReadAllLines($full).Count }
        $mod = $relp.Split('/')[0]
        "{0,2}  {1,-14} {2,5} lines  {3}" -f $i, $mod, $count, $relp
      }
      "--  (not in load order) pfpalette/pfp-proof.lsp, Diagnostic_Tools/*.lsp"
      return
    }

    'grep' {
      if ($a.Count -lt 1) { Write-Error 'usage: pf grep <regex>'; return }
      Search-PfTree $a[0] @('.lsp')
      return
    }

    default { Show-PfUsage; return }
  }
}
