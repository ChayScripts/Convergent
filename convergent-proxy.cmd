@echo off
rem ===========================================================================
rem  convergent-proxy.cmd
rem  ---------------------
rem  Lightweight CORS proxy for Convergent - lets the browser reach NVIDIA NIM
rem  (and any other CORS-blocked API) from a local file:// or localhost origin.
rem
rem  Windows port of convergent-proxy.js. No Node.js required: the batch
rem  wrapper parses arguments and then runs the PowerShell server embedded at
rem  the bottom of this same file.
rem
rem  Usage
rem    convergent-proxy.cmd [--port 3030]
rem    convergent-proxy.cmd --help
rem
rem  How it works
rem    The browser sends requests to http://127.0.0.1:<port>/proxy?url=<target>
rem    The proxy forwards them server-side (no CORS restriction) and streams
rem    the response back with the appropriate CORS headers.
rem
rem    GET /health backs the "Test Proxy Connection" button.
rem
rem    Each connection is handled in its own runspace, so idle sockets (the
rem    browser preconnects spares and sends nothing on them) cannot block
rem    real requests.
rem
rem  Security note
rem    Binds to 127.0.0.1 only and forwards only to HTTPS hosts on the
rem    whitelist below. NOT for production - run it locally only.
rem ===========================================================================

setlocal
set "CP_SELF=%~f0"
set "CP_PORT="
set "CP_GIVEN="

rem -- Argument parsing -------------------------------------------------------
:parse
if "%~1"=="" goto validate
if /i "%~1"=="--port" (set "CP_GIVEN=1" & set "CP_PORT=%~2" & shift & shift & goto parse)
if /i "%~1"=="-p"     (set "CP_GIVEN=1" & set "CP_PORT=%~2" & shift & shift & goto parse)
if /i "%~1"=="--help" goto help
if /i "%~1"=="-h"     goto help
if /i "%~1"=="/?"     goto help
echo Unknown option: %~1
echo Try: "%~nx0" --help
exit /b 1

:help
echo.
echo   Convergent CORS Proxy (Windows)
echo.
echo   Usage:  "%~nx0" [--port ^<number^>]
echo.
echo     --port, -p   TCP port to listen on (default 3030)
echo     --help, -h   Show this message
echo.
echo   Routes:  /health                        health check
echo            /proxy?url=^<encoded-target^>    forwarding endpoint
echo.
exit /b 0

:validate
if not defined CP_GIVEN goto findps
if not defined CP_PORT goto badport
echo(%CP_PORT%|findstr /r /c:"^[0-9][0-9]*$" >nul || goto badport
if %CP_PORT% LSS 1 goto badport
if %CP_PORT% GTR 65535 goto badport
goto findps

:badport
echo Invalid port: %CP_PORT%
exit /b 1

:findps
rem -- Locate a PowerShell host ----------------------------------------------
set "PSEXE="
where powershell.exe >nul 2>nul && set "PSEXE=powershell.exe"
if not defined PSEXE (
  where pwsh.exe >nul 2>nul && set "PSEXE=pwsh.exe"
)
if not defined PSEXE (
  echo PowerShell was not found on PATH. It is required to run this proxy.
  exit /b 1
)

rem -- Run the embedded PowerShell server ------------------------------------
%PSEXE% -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:CP_SELF);$i=$s.LastIndexOf('#::PSBODY');if($i -lt 0){Write-Host 'Embedded server code not found - file is corrupt.';exit 1};Invoke-Expression $s.Substring($i)"
exit /b %ERRORLEVEL%


#::PSBODY
# ===========================================================================
#  Embedded PowerShell server. Everything below this marker is read and
#  executed by the batch wrapper above; cmd.exe never parses it.
# ===========================================================================

$VERSION      = '1.2.0'
$DEFAULT_PORT = 3030
$MAX_WORKERS  = 16

# Only forward to these hosts (whitelist to prevent open-proxy abuse)
$ALLOWED_HOSTS = @(
  'integrate.api.nvidia.com',
  'api.openai.com',
  'generativelanguage.googleapis.com',
  'api.groq.com',
  'api.together.xyz',
  'api.mistral.ai',
  'api.anthropic.com',
  'api.cloudflare.com',
  'indierouter.ai'
  # Add more as needed. Matching is "exact host, or any SUBDOMAIN of an entry",
  # so 'indierouter.ai' covers 'api.indierouter.ai' - but NOT the other way
  # round. Always list the parent domain.
)

$port = $DEFAULT_PORT
if ($env:CP_PORT) { $port = [int]$env:CP_PORT }

# Modern TLS + no 100-continue stall on POSTs. These are process-wide statics,
# so setting them here also covers every worker runspace.
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]'Tls12,Tls13'
} catch {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
[Net.ServicePointManager]::Expect100Continue = $false
[Net.ServicePointManager]::DefaultConnectionLimit = 64

# ===========================================================================
#  Per-connection worker. Runs in its own runspace, so it must be
#  self-contained - it cannot see functions defined in the main scope.
# ===========================================================================
$worker = {
  param($client, $cfg)

  function Write-Log([string]$msg, [string]$color) {
    try {
      if ($color) { Write-Host $msg -ForegroundColor $color } else { Write-Host $msg }
    } catch { }   # never let a console-write race kill a request
  }

  # -- CORS headers sent on every response ----------------------------------
  function Add-Cors($h, $acrh) {
    $h['Access-Control-Allow-Origin']  = '*'
    $h['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS, DELETE, PUT, PATCH'
    # Echo back whatever the browser asked to send. A fixed list silently fails
    # any client that adds its own headers (the OpenAI SDK sends x-stainless-*,
    # Anthropic sends anthropic-version), and the request never leaves at all.
    if ($acrh) {
      $h['Access-Control-Allow-Headers'] = $acrh
    } else {
      $h['Access-Control-Allow-Headers'] = 'Authorization, Content-Type, Accept, X-Api-Key, X-Target-Auth'
    }
    $h['Access-Control-Max-Age']       = '86400'
    # Chrome's Private Network Access check: required when the calling page is
    # served over https and the proxy lives on loopback
    $h['Access-Control-Allow-Private-Network'] = 'true'
  }

  function Send-Head($stream, [int]$status, [string]$reason, $headers) {
    if (-not $reason) { $reason = 'Status' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('HTTP/1.1 ' + $status + ' ' + $reason + "`r`n")
    foreach ($k in $headers.Keys) {
      [void]$sb.Append($k + ': ' + $headers[$k] + "`r`n")
    }
    [void]$sb.Append("`r`n")
    $bytes = [Text.Encoding]::ASCII.GetBytes($sb.ToString())
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
  }

  function Send-Text($stream, [int]$status, [string]$reason, [string]$text, [string]$ctype) {
    $body = [Text.Encoding]::UTF8.GetBytes($text)
    $h = [ordered]@{}
    Add-Cors $h
    if ($ctype) { $h['Content-Type'] = $ctype }
    $h['Content-Length'] = $body.Length
    $h['Connection']     = 'close'
    Send-Head $stream $status $reason $h
    if ($body.Length) { $stream.Write($body, 0, $body.Length); $stream.Flush() }
  }

  # -- Request reading ------------------------------------------------------
  # Returns $null on timeout or disconnect. An idle socket is normal (browsers
  # preconnect spares), so the caller treats $null as "nothing to do".
  function Read-Head($stream) {
    $buf = New-Object System.Collections.Generic.List[byte]
    $one = New-Object byte[] 1
    while ($true) {
      try {
        $n = $stream.Read($one, 0, 1)
      } catch {
        return $null
      }
      if ($n -le 0) { return $null }
      $buf.Add($one[0])
      $c = $buf.Count
      if ($c -ge 4 -and $buf[$c-4] -eq 13 -and $buf[$c-3] -eq 10 -and $buf[$c-2] -eq 13 -and $buf[$c-1] -eq 10) { break }
      if ($c -gt 65536) { return $null }
    }
    [Text.Encoding]::ASCII.GetString($buf.ToArray())
  }

  function Read-Exact($stream, [int]$count) {
    $buf = New-Object byte[] $count
    $off = 0
    while ($off -lt $count) {
      try {
        $n = $stream.Read($buf, $off, $count - $off)
      } catch {
        break
      }
      if ($n -le 0) { break }
      $off += $n
    }
    ,$buf
  }

  # -- Request handler -----------------------------------------------------
  function Invoke-Handler($stream, $cfg) {
    $head = Read-Head $stream
    if (-not $head) { return }          # idle or dropped connection

    $lines = $head -split "`r`n"
    $bits  = $lines[0] -split '\s+'
    if ($bits.Count -lt 2) {
      Send-Text $stream 400 'Bad Request' 'Malformed request line' 'text/plain'
      return
    }
    $method  = $bits[0].ToUpper()
    $rawPath = $bits[1]

    $hdrs = @{}
    for ($i = 1; $i -lt $lines.Count; $i++) {
      $l = $lines[$i]
      if (-not $l) { continue }
      $ci = $l.IndexOf(':')
      if ($ci -gt 0) { $hdrs[$l.Substring(0, $ci).Trim().ToLower()] = $l.Substring($ci + 1).Trim() }
    }

    # Read the body before answering, so the socket stays in sync
    $body = $null
    $clen = 0
    if ($hdrs['content-length']) { [void][int]::TryParse($hdrs['content-length'], [ref]$clen) }
    if ($clen -gt 0) { $body = Read-Exact $stream $clen }

    # -- Preflight --
    if ($method -eq 'OPTIONS') {
      $h = [ordered]@{}
      Add-Cors $h $hdrs['access-control-request-headers']
      $h['Content-Length'] = '0'
      $h['Connection']     = 'close'
      Send-Head $stream 204 'No Content' $h
      return
    }

    $qIdx     = $rawPath.IndexOf('?')
    $pathOnly = if ($qIdx -ge 0) { $rawPath.Substring(0, $qIdx) } else { $rawPath }
    $queryStr = if ($qIdx -ge 0) { $rawPath.Substring($qIdx + 1) } else { '' }

    # -- Health check --
    if ($pathOnly -eq '/health') {
      $json = '{"status":"ok","version":"' + $cfg.Version + '","port":' + $cfg.Port + '}'
      Send-Text $stream 200 'OK' $json 'application/json'
      return
    }

    # -- Proxy route --
    if ($pathOnly -eq '/proxy') {
      $rawTarget = $null
      foreach ($pair in $queryStr.Split('&')) {
        if (-not $pair) { continue }
        $eq = $pair.IndexOf('=')
        $k  = if ($eq -ge 0) { $pair.Substring(0, $eq) } else { $pair }
        $v  = if ($eq -ge 0) { $pair.Substring($eq + 1) } else { '' }
        if ($k -eq 'url') { $rawTarget = [Uri]::UnescapeDataString($v.Replace('+', '%20')) }
      }

      if (-not $rawTarget) {
        Send-Text $stream 400 'Bad Request' 'Missing ?url= parameter' 'text/plain'
        return
      }

      $target = $null
      try { $target = [Uri]$rawTarget } catch { $target = $null }
      if (-not $target -or -not $target.IsAbsoluteUri) {
        Send-Text $stream 400 'Bad Request' 'Invalid target URL' 'text/plain'
        return
      }

      # Only allow HTTPS targets
      if ($target.Scheme -ne 'https') {
        Send-Text $stream 403 'Forbidden' 'Only HTTPS targets are allowed' 'text/plain'
        return
      }

      # Whitelist check (exact host or any subdomain of an allowed host)
      $thost = $target.Host
      $ok = $false
      foreach ($a in $cfg.AllowedHosts) {
        if ($thost -eq $a -or $thost.EndsWith('.' + $a)) { $ok = $true; break }
      }
      if (-not $ok) {
        Write-Log ('[proxy] Blocked request to: ' + $thost) 'Yellow'
        Send-Text $stream 403 'Forbidden' ('Target host not in allowed list: ' + $thost) 'text/plain'
        return
      }

      # Build forwarded request - hop-by-hop headers are simply not copied
      $req = [System.Net.HttpWebRequest]::Create($target)
      $req.Method            = if ($method -eq 'GET') { 'GET' } else { 'POST' }
      $req.ContentType       = if ($hdrs['content-type']) { $hdrs['content-type'] } else { 'application/json' }
      $req.Accept            = if ($hdrs['accept']) { $hdrs['accept'] } else { 'application/json' }
      $req.UserAgent         = 'convergent-proxy/' + $cfg.Version
      $req.Proxy             = $null
      $req.KeepAlive         = $false
      $req.AllowAutoRedirect = $true
      $req.Timeout           = 120000
      $req.ReadWriteTimeout  = 600000

      # Map custom auth header -> Authorization (Convergent sends X-Target-Auth)
      $auth = $null
      if     ($hdrs['x-target-auth']) { $auth = $hdrs['x-target-auth'] }
      elseif ($hdrs['x-api-key'])     { $auth = 'Bearer ' + $hdrs['x-api-key'] }
      elseif ($hdrs['authorization']) { $auth = $hdrs['authorization'] }
      if ($auth) { $req.Headers['Authorization'] = $auth }

      # Pass through any other client headers the gateway may need
      # (HTTP-Referer, X-Title, anthropic-version, OpenAI-Organization...).
      # Restricted headers are set via properties above, hop-by-hop and
      # browser-noise headers are dropped.
      $skip = @(
        'host','connection','content-length','transfer-encoding','keep-alive',
        'upgrade','te','trailer','proxy-connection','expect','date','range',
        'accept','content-type','user-agent','referer','origin','cookie',
        'accept-encoding','authorization','x-target-auth','x-api-key',
        'access-control-request-headers','access-control-request-method'
      )
      foreach ($k in $hdrs.Keys) {
        if ($skip -contains $k) { continue }
        if ($k.StartsWith('sec-')) { continue }
        try { $req.Headers[$k] = $hdrs[$k] } catch { }
      }

      # Let .NET strip any Content-Encoding, so the browser is never handed
      # compressed bytes labelled as application/json
      $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

      if ($body -and $body.Length) {
        $req.ContentLength = $body.Length
        $rs = $req.GetRequestStream()
        $rs.Write($body, 0, $body.Length)
        $rs.Close()
      }

      $shown = $target.AbsoluteUri
      if ($shown.Length -gt 120) { $shown = $shown.Substring(0, 120) }
      Write-Log ('[proxy] ' + $req.Method + ' ' + $shown)

      $resp = $null
      try {
        $resp = $req.GetResponse()
      } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
          $resp = $_.Exception.Response      # forward 4xx/5xx bodies verbatim
        } else {
          Write-Log ('[proxy] request error: ' + $_.Exception.Message) 'Red'
          Send-Text $stream 502 'Bad Gateway' ('Proxy error: ' + $_.Exception.Message) 'text/plain'
          return
        }
      }

      $status = [int]$resp.StatusCode
      $reason = $resp.StatusDescription
      $ctype  = $resp.Headers['Content-Type']

      $h = [ordered]@{}
      Add-Cors $h
      # Forward content-type so browser can parse JSON/SSE correctly
      if ($ctype) { $h['Content-Type'] = $ctype }
      # Stream mode (SSE) - disable buffering
      if ($ctype -and $ctype.Contains('text/event-stream')) {
        $h['Cache-Control']     = 'no-cache'
        $h['X-Accel-Buffering'] = 'no'
      }
      $h['Connection'] = 'close'

      $ins   = $resp.GetResponseStream()
      $isSse = $ctype -and $ctype.Contains('text/event-stream')

      if ($status -ge 400 -and -not $isSse) {
        # Buffer the failure so its reason reaches the console. Without this a
        # 401/403 looks identical to "no models" in the browser.
        $ms = New-Object System.IO.MemoryStream
        try { $ins.CopyTo($ms) } catch { }
        $errBytes = $ms.ToArray()
        $snippet  = [Text.Encoding]::UTF8.GetString($errBytes)
        if ($snippet.Length -gt 300) { $snippet = $snippet.Substring(0, 300) + '...' }
        Write-Log ('[proxy] <- ' + $status + ' ' + $snippet) 'Yellow'
        $h['Content-Length'] = $errBytes.Length
        Send-Head $stream $status $reason $h
        if ($errBytes.Length) { $stream.Write($errBytes, 0, $errBytes.Length); $stream.Flush() }
        $ins.Close(); $resp.Close()
        return
      }

      Write-Log ('[proxy] <- ' + $status + ' ' + $ctype)
      # Response is delimited by connection close, so no Content-Length
      Send-Head $stream $status $reason $h

      $buf = New-Object byte[] 16384
      try {
        while ($true) {
          $n = $ins.Read($buf, 0, $buf.Length)
          if ($n -le 0) { break }
          $stream.Write($buf, 0, $n)
          $stream.Flush()
        }
      } catch {
        Write-Log ('[proxy] upstream error: ' + $_.Exception.Message) 'Red'
      } finally {
        $ins.Close()
        $resp.Close()
      }
      return
    }

    # -- Unknown route --
    Write-Log ('[proxy] 404 ' + $method + ' ' + $pathOnly + '  (app is not using the /proxy route)') 'Yellow'
    Send-Text $stream 404 'Not Found' 'Not found. Valid routes: /health  /proxy?url=<encoded-target>' 'text/plain'
  }

  # -- Worker entry point --------------------------------------------------
  try {
    $client.NoDelay = $true
    $stream = $client.GetStream()
    $stream.ReadTimeout  = 15000
    $stream.WriteTimeout = 600000
    Invoke-Handler $stream $cfg
  } catch [System.IO.IOException] {
    # Socket read/write timeouts and resets are routine here: the browser
    # opens spare connections it never uses, and cancels in-flight streams.
    # Nothing actionable, so stay quiet.
  } catch {
    Write-Log ('[proxy] error: ' + $_.Exception.Message) 'Red'
  } finally {
    try { $client.Close() } catch { }
  }
}

# ===========================================================================
#  Start server
# ===========================================================================
$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $port)
try {
  $listener.Start()
} catch {
  Write-Host ('Port ' + $port + ' is already in use (or unavailable). Try: convergent-proxy.cmd --port ' + ($port + 1)) -ForegroundColor Red
  exit 1
}

$BOX_W = 45
function Show-Rule { Write-Host ('  +' + ('-' * $BOX_W) + '+') }
function Show-Line([string]$text) {
  $inner = '  ' + $text
  if ($inner.Length -gt $BOX_W) { $inner = $inner.Substring(0, $BOX_W) }
  Write-Host ('  |' + $inner.PadRight($BOX_W) + '|')
}

Write-Host ''
Show-Rule
Show-Line ('      Convergent CORS Proxy  v' + $VERSION)
Show-Rule
Show-Line ('Listening on  http://127.0.0.1:' + $port)
Show-Line ('Health check  http://127.0.0.1:' + $port + '/health')
Show-Line ''
Show-Line 'In Convergent -> Settings -> Endpoints'
Show-Line 'CORS Proxy section -> enter URL above'
Show-Line 'and click "Test Proxy Connection"'
Show-Line ''
Show-Line 'Press Ctrl+C to stop'
Show-Rule
Write-Host ''

$cfg = @{
  Version      = $VERSION
  Port         = $port
  AllowedHosts = $ALLOWED_HOSTS
}

# $Host is passed so worker runspaces can write to this console
$pool = [runspacefactory]::CreateRunspacePool(1, $MAX_WORKERS, $Host)
$pool.ApartmentState = 'MTA'
$pool.Open()

$running    = New-Object System.Collections.ArrayList
$workerText = $worker.ToString()

function Remove-Finished($running) {
  for ($i = $running.Count - 1; $i -ge 0; $i--) {
    $j = $running[$i]
    if ($j.Async.IsCompleted) {
      try { [void]$j.PS.EndInvoke($j.Async) } catch { }
      $j.PS.Dispose()
      $running.RemoveAt($i)
    }
  }
}

try {
  while ($true) {
    # AcceptTcpClient blocks inside .NET, and PowerShell can only act on Ctrl+C
    # between statements - so block there and the key press is ignored until
    # the next connection arrives. Poll instead: Pending() returns immediately
    # and Start-Sleep is an interruptible safe point.
    if (-not $listener.Pending()) {
      Remove-Finished $running
      Start-Sleep -Milliseconds 50
      continue
    }

    $client = $listener.AcceptTcpClient()

    # Hand the socket to a worker and go straight back to accepting, so a
    # connection that sends nothing cannot hold up the queue
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($workerText).AddArgument($client).AddArgument($cfg)
    $async = $ps.BeginInvoke()
    [void]$running.Add([pscustomobject]@{ PS = $ps; Async = $async })

    Remove-Finished $running
  }
} finally {
  # Graceful shutdown (Ctrl+C)
  try { $listener.Stop() } catch { }
  Remove-Finished $running
  try { $pool.Close(); $pool.Dispose() } catch { }
  Write-Host ''
  Write-Host 'Proxy stopped.'
}
