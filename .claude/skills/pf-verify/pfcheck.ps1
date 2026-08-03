# pfcheck.ps1 -- static gates for the pfsuite AutoLISP tree.
# Everything here is checkable WITHOUT AutoCAD. Run it instead of re-reading
# files to convince yourself an edit is sound. CAD gates are in SKILL.md.
#
# Execution policy blocks running .ps1 files on locked-down machines, so this is
# loaded by content, not by path:
#   Invoke-Expression (Get-Content -Raw .claude\skills\pf-verify\pfcheck.ps1); pfcheck
#
# PowerShell 5.1 compatible. No ternary, no ??, no external binaries.
# No Set-StrictMode / Set-Location here: this file is evaluated in the caller's
# session, so anything set at top level leaks into it.

function Get-PfcRoot {
  $d = (Get-Location).Path
  while ($d) {
    if (Test-Path (Join-Path $d 'pfsuite\pftools-load.lsp')) { return $d }
    $p = Split-Path $d -Parent
    if ($p -eq $d) { break }
    $d = $p
  }
  throw "pfcheck: cannot find the V5 root (no pfsuite\pftools-load.lsp above $((Get-Location).Path))"
}

# Sort-Object is culture-aware and ignores punctuation, so "pfp-proof.lsp" and
# "pfpalette.lsp" come out in the opposite order from a byte comparison. Every
# ordering here is ordinal so it matches the tree walk it replaced.
function Sort-PfcOrdinal { param([object[]]$Items, [string]$Property)
  # @($null) is a 1-element array holding null, not an empty array -- an empty
  # result must stay empty or callers see one phantom item.
  $a = @()
  if ($null -ne $Items) { $a = @($Items | Where-Object { $null -ne $_ }) }
  if ($a.Count -lt 2) { return $a }
  $cmp = [System.Comparison[object]]{
    param($x, $y)
    $sx = $x; $sy = $y
    if ($Property -ne '') { $sx = $x.$Property; $sy = $y.$Property }
    return [string]::CompareOrdinal([string]$sx, [string]$sy)
  }
  [System.Array]::Sort($a, $cmp)
  return $a
}

function Get-PfcLsp { param([string]$Src)
  Sort-PfcOrdinal (Get-ChildItem -Path $Src -Filter *.lsp -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\Opendcl_Reference\\' -and
                   $_.FullName -notmatch '\\_attic\\' }) 'FullName'
}

function Get-PfcRel { param([string]$Full, [string]$Src)
  $p = $Src + '\'
  if ($Full.StartsWith($p)) { return $Full.Substring($p.Length).Replace('\','/') }
  return $Full.Replace('\','/')
}

# Strip string literals and ; comments so checks never trip on prose.
function ConvertTo-PfcCodeOnly { param([string]$Line)
  $sb = New-Object System.Text.StringBuilder
  $instr = $false
  $ch = $Line.ToCharArray()
  for ($i = 0; $i -lt $ch.Length; $i++) {
    $c = $ch[$i]
    if ($instr) {
      if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $instr = $false }
      continue
    }
    if ($c -eq '"') { $instr = $true; [void]$sb.Append(' '); continue }
    if ($c -eq ';') { break }
    [void]$sb.Append($c)
  }
  return $sb.ToString()
}

# Strip ; comments but KEEP string literals -- DCL callbacks are wired as
# strings, e.g. (action_tile "accept" "(pfs:ok)"), and those are real calls.
function ConvertTo-PfcNoComments { param([string]$Line)
  $sb = New-Object System.Text.StringBuilder
  $instr = $false
  $ch = $Line.ToCharArray()
  for ($i = 0; $i -lt $ch.Length; $i++) {
    $c = $ch[$i]
    if ($instr) {
      [void]$sb.Append($c)
      if ($c -eq '\') { $i++; if ($i -lt $ch.Length) { [void]$sb.Append($ch[$i]) } }
      elseif ($c -eq '"') { $instr = $false }
      continue
    }
    if ($c -eq '"') { $instr = $true; [void]$sb.Append($c); continue }
    if ($c -eq ';') { break }
    [void]$sb.Append($c)
  }
  return $sb.ToString()
}

function pfcheck {
  [CmdletBinding()]
  param([string]$Only = 'all')

  $Root = Get-PfcRoot
  $Src  = Join-Path $Root 'pfsuite'
  $fail = $false

  $symRe    = New-Object System.Text.RegularExpressions.Regex '\bpf[a-z]*:[A-Za-z0-9>_-]+'
  $defunRe  = New-Object System.Text.RegularExpressions.Regex '^\(defun'
  $hdrStrip = New-Object System.Text.RegularExpressions.Regex '^\(defun[ \t][ \t]*[^ \t()]*'

  $files = @(Get-PfcLsp $Src)

  # ---- shared tables -------------------------------------------------------
  # defs: symbol / rel / line
  $defs = New-Object System.Collections.Generic.List[object]
  foreach ($f in $files) {
    $rel = Get-PfcRel $f.FullName $Src
    $n = 0
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
      $n++
      if (-not $defunRe.IsMatch($line)) { continue }
      $name = $line -replace '^\(defun[ \t]+', ''
      $name = $name -replace '[ \t()].*$', ''
      $defs.Add((New-Object PSObject -Property @{ Name = $name; Rel = $rel; Line = $n }))
    }
  }

  # uses: symbol / rel  (code references only; a defun's own header line is NOT
  # a use of itself, or nothing would ever look dead)
  $uses = New-Object System.Collections.Generic.List[object]
  foreach ($f in $files) {
    $rel = Get-PfcRel $f.FullName $Src
    $seen = New-Object System.Collections.Generic.SortedSet[string] ([StringComparer]::Ordinal)
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
      $code = $hdrStrip.Replace((ConvertTo-PfcCodeOnly $line), '', 1)
      foreach ($m in $symRe.Matches($code)) { [void]$seen.Add($m.Value) }
    }
    foreach ($s in $seen) {
      $uses.Add((New-Object PSObject -Property @{ Sym = $s.ToLowerInvariant(); Rel = $rel }))
    }
  }

  $defined = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::Ordinal)
  foreach ($d in $defs) { [void]$defined.Add($d.Name.ToLowerInvariant()) }

  # reached: uses PLUS names called from .dcl/.odcl action strings and OpenDCL
  # event wiring -- those are real callers the .lsp scan cannot see.
  $reached = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::Ordinal)
  foreach ($u in $uses) { [void]$reached.Add($u.Sym) }
  foreach ($f in $files) {
    foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
      $code = $hdrStrip.Replace((ConvertTo-PfcNoComments $line), '', 1)
      foreach ($m in $symRe.Matches($code)) { [void]$reached.Add($m.Value.ToLowerInvariant()) }
    }
  }
  $dcl = Get-ChildItem -Path $Src -Recurse -File |
    Where-Object { ($_.Extension -eq '.dcl' -or $_.Extension -eq '.odcl') -and
                   $_.FullName -notmatch '\\Opendcl_Reference\\' }
  foreach ($f in $dcl) {
    # .odcl is binary; read as latin-1 so byte-ish content still yields matches.
    $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::GetEncoding(28591))
    foreach ($m in $symRe.Matches($text)) { [void]$reached.Add($m.Value.ToLowerInvariant()) }
  }

  # order: rel -> load index (the line number in pftools-load.lsp; monotonic)
  $ord = @{}
  $n = 0
  foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $Src 'pftools-load.lsp'))) {
    $n++
    if ($line -notmatch '\(load \(strcat \*pftools-dir\*') { continue }
    $parts = $line.Split('"')
    if ($parts.Count -lt 2) { continue }
    $ord[$parts[1]] = $n
  }

  # ---- 1. paren balance ----------------------------------------------------
  if ($Only -eq 'all' -or $Only -eq 'parens') {
    "`n== paren balance =="
    foreach ($f in $files) {
      $rel = Get-PfcRel $f.FullName $Src
      $depth = 0; $instr = $false; $top = 0; $reported = $false
      $n = 0
      foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
        $n++
        $ch = $line.ToCharArray()
        for ($i = 0; $i -lt $ch.Length; $i++) {
          $c = $ch[$i]
          if ($instr) {
            if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $instr = $false }
            continue
          }
          if ($c -eq '"') { $instr = $true; continue }
          if ($c -eq ';') { break }
          if ($c -eq '(') { $depth++; if ($depth -eq 1) { $top = $n } }
          elseif ($c -eq ')') {
            $depth--
            if ($depth -lt 0) { "  FAIL {0}:{1}  unmatched )" -f $rel, $n; $reported = $true; break }
          }
        }
        if ($reported) { break }
      }
      if ($reported) { $fail = $true }
      elseif ($instr) { "  FAIL {0}  unterminated string" -f $rel; $fail = $true }
      elseif ($depth -gt 0) { "  FAIL {0}  {1} unclosed ( -- outermost form opens at line {2}" -f $rel, $depth, $top; $fail = $true }
      else { "  ok   {0}" -f $rel }
    }
  }

  # ---- 2. duplicate defuns -------------------------------------------------
  if ($Only -eq 'all' -or $Only -eq 'dupes') {
    "`n== duplicate defuns =="
    $byName = @{}
    foreach ($d in $defs) {
      $k = $d.Name.ToLowerInvariant()
      if (-not $byName.ContainsKey($k)) { $byName[$k] = New-Object System.Collections.Generic.List[object] }
      $byName[$k].Add($d)
    }
    $dupes = @(Sort-PfcOrdinal ($byName.Keys | Where-Object { $byName[$_].Count -gt 1 }) '')
    if ($dupes.Count -gt 0) {
      $fail = $true
      foreach ($d in $dupes) {
        "  FAIL {0} defined more than once:" -f $d
        foreach ($e in $byName[$d]) { "         {0}:{1}" -f $e.Rel, $e.Line }
      }
    } else { "  ok   no symbol defined twice" }
  }

  # ---- 3. called but never defined ----------------------------------------
  if ($Only -eq 'all' -or $Only -eq 'undefined') {
    "`n== called but never defined =="
    $used = New-Object System.Collections.Generic.SortedSet[string] ([StringComparer]::Ordinal)
    foreach ($u in $uses) { [void]$used.Add($u.Sym) }
    $miss = @($used | Where-Object { -not $defined.Contains($_) })
    if ($miss.Count -gt 0) {
      $fail = $true
      foreach ($m in $miss) {
        $where = ''
        foreach ($u in $uses) { if ($u.Sym -eq $m) { $where += ($u.Rel + ' ') } }
        "  FAIL {0} -- no defun; called from: {1}" -f $m, $where
      }
    } else { "  ok   every pf* symbol called has a defun" }
  }

  # ---- 4. load-order violations -------------------------------------------
  if ($Only -eq 'all' -or $Only -eq 'order') {
    "`n== load-order guardrail (a file may only use symbols from files above it) =="
    $base = Join-Path $Root '.claude\pf-index\order-baseline.txt'
    if (-not (Test-Path $base)) {
      $bd = Split-Path $base -Parent
      if (-not (Test-Path $bd)) { New-Item -ItemType Directory -Force $bd | Out-Null }
      [System.IO.File]::WriteAllText($base, '', (New-Object System.Text.UTF8Encoding $false))
    }
    $owner = @{}
    foreach ($d in $defs) {
      $k = $d.Name.ToLowerInvariant()
      if (-not $owner.ContainsKey($k)) { $owner[$k] = $d.Rel }
    }
    $viol = New-Object System.Collections.Generic.SortedSet[string] ([StringComparer]::Ordinal)
    foreach ($u in $uses) {
      if (-not $owner.ContainsKey($u.Sym)) { continue }
      $o = $owner[$u.Sym]
      if ($o -eq $u.Rel) { continue }
      if (-not $ord.ContainsKey($u.Rel)) { continue }      # unloaded helpers: skip
      if (-not $ord.ContainsKey($o)) { continue }
      if ($ord[$o] -gt $ord[$u.Rel]) {
        [void]$viol.Add(("{0} uses {1} (owned by {2}, loads later)" -f $u.Rel, $u.Sym, $o))
      }
    }
    $baseSet = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::Ordinal)
    foreach ($l in [System.IO.File]::ReadAllLines($base)) { if ($l -ne '') { [void]$baseSet.Add($l) } }
    $new   = @($viol | Where-Object { -not $baseSet.Contains($_) })
    $known = @($viol | Where-Object { $baseSet.Contains($_) })
    if ($new.Count -gt 0) {
      foreach ($l in $new) { "  FAIL {0}" -f $l }
      $fail = $true
      "  (sanctioned? document it in the module README, then append the line to"
      "   .claude/pf-index/order-baseline.txt -- do NOT baseline it silently)"
    } else {
      "  ok   no NEW forward reference ({0} baselined, all documented as resolved-at-call-time)" -f $known.Count
    }
  }

  # ---- 5. defined but never referenced ------------------------------------
  if ($Only -eq 'all' -or $Only -eq 'dead') {
    "`n== defined but never referenced in .lsp code, .dcl or .odcl (dead-code candidates) =="
    $n = 0
    foreach ($d in $defs) {
      $low = $d.Name.ToLowerInvariant()
      if ($low.StartsWith('c:')) { continue }              # commands + OpenDCL handlers
      if ($reached.Contains($low)) { continue }
      "  note {0,-28} {1}:{2}" -f $d.Name, $d.Rel, $d.Line
      $n++
    }
    if ($n -eq 0) { "  ok   none" }
    else { "  ({0} -- advisory, not a failure: reachable only by name land here)" -f $n }
  }

  # ---- 6. README Public API drift -----------------------------------------
  if ($Only -eq 'all' -or $Only -eq 'api') {
    "`n== README 'Public API' entries with no matching defun =="
    $readmes = @(Sort-PfcOrdinal (Get-ChildItem -Path $Src -Directory |
                 ForEach-Object { Join-Path $_.FullName 'README.md' } |
                 Where-Object { Test-Path $_ }) '')
    if ($readmes.Count -eq 0) { "  ok   no module READMEs" }
    else {
      $tickRe = New-Object System.Text.RegularExpressions.Regex '`pf[a-z]*:[A-Za-z0-9>_-]+'
      $seen = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::Ordinal)
      $n = 0
      foreach ($r in $readmes) {
        $mod = Split-Path (Split-Path $r -Parent) -Leaf
        $on = $false
        foreach ($line in [System.IO.File]::ReadAllLines($r)) {
          if ($line -match '^## Public API') { $on = $true; continue }
          if ($on -and $line -match '^## ') { $on = $false }
          if (-not $on) { continue }
          foreach ($m in $tickRe.Matches($line)) {
            $t = $m.Value.Substring(1)
            if ($t.EndsWith('-')) { continue }             # `pfa:xr-*` family shorthand
            if ($defined.Contains($t.ToLowerInvariant())) { continue }
            if (-not $seen.Add($mod + '|' + $t)) { continue }
            "  note {0}/README.md documents {1} -- no defun" -f $mod, $t
            $n++
          }
        }
      }
      if ($n -eq 0) { "  ok   every documented symbol exists" }
    }
  }

  ''
  if (-not $fail) { 'STATIC GATES: PASS' } else { 'STATIC GATES: FAIL' }
  if ($fail) { return 1 } else { return 0 }
}
