<#
.SYNOPSIS
    PowerShell port of testGetPatInfo.pl - calls the CarlX PatronAPI
    GetPatronInformation SOAP operation for a list of patron IDs.

.DESCRIPTION
    Reads the SOAP endpoint address out of the CarlX PatronAPI WSDL
    (PatronAPInew.wsdl by default, PatronAPI.wsdl with -Production),
    builds a GetPatronInformationRequest SOAP 1.1 envelope for each
    patron ID, and posts it directly with Invoke-WebRequest.

    NOTE: PowerShell 7/Core has no equivalent to Windows PowerShell's
    New-WebServiceProxy (it depends on System.Web.Services, which does
    not exist in .NET / PowerShell Core). Because of that, this script
    talks SOAP "by hand" - building the envelope as XML text and parsing
    the response XML - rather than generating a typed client proxy from
    the WSDL the way XML::Compile::WSDL11 does in the Perl original.

    The request field namespaces (patronAPI vs request schema) were
    derived from PatronAPInew.wsdl. Response parsing uses local-name()
    XPath lookups so it does not depend on getting every namespace
    prefix exactly right, but deeply nested/optional structures (e.g.
    User Defined Fields) are labeled generically - inspect -Raw output
    against a live response and adjust ConvertFrom-CarlXPatronResponse
    if your UDF labels differ.

    Error handling: transient request failures (timeouts, connection
    errors) are retried up to -RetryCount times with a short backoff.
    SOAP faults and non-zero ResponseStatusCode values are surfaced in
    the result objects and logged as warnings, not treated as fatal.
    Anything unexpected (missing WSDL, unparsable response, etc.) is
    logged at FATAL and causes the process to exit non-zero, so this
    script's exit code can be checked by callers/schedulers.

    NOTE ON exit: this script is meant to be invoked directly (e.g.
    .\Get-PatronInfo.ps1 ... or pwsh -File .\Get-PatronInfo.ps1 ...).
    It calls exit to set the process exit code for automation. Do not
    dot-source it (. .\Get-PatronInfo.ps1) in an interactive session,
    since exit would close that session.

.PARAMETER InputFile
    Path to a CSV file where each line is patronid,name,bty,email (only
    the first column, the patron barcode/ID, is used). If omitted, the
    script reads patron ID lines from the pipeline/stdin instead - e.g.
    echo "11982021684457" | .\Get-PatronInfo.ps1

.PARAMETER LogLevel
    One of TRACE, DEBUG, INFO, WARN, ERROR, FATAL. Default INFO.

.PARAMETER LogFile
    Optional path to append timestamped log lines to, in addition to
    the console. The parent directory is created if it doesn't exist.

.PARAMETER Production
    Use PatronAPI.wsdl (production endpoint) instead of the default
    PatronAPInew.wsdl (test/new endpoint). Mirrors the Perl script's -p
    option. BE CAREFUL with this switch against production.

.PARAMETER ThrottleLimit
    Max number of patron lookups to run concurrently. Mirrors MCE::Loop's
    max_workers => 8 in the Perl original. Default 8.

.PARAMETER TimeoutSec
    Per-request HTTP timeout, in seconds. Default 30.

.PARAMETER RetryCount
    Number of retries after a failed request attempt due to a transient
    error (timeout, connection failure, 5xx, etc.) before giving up on
    that patron ID. SOAP faults returned with a body are not retried,
    since they are a real (non-transient) API response. Default 2.

.PARAMETER OutputCsv
    Optional path to write results as CSV.

.PARAMETER Credential
    Optional PSCredential if the CarlX PatronAPI endpoint requires HTTP
    Basic authentication. Not required by the original script, but many
    CarlX installs sit behind Basic auth or a reverse proxy that does.

.EXAMPLE
    .\Get-PatronInfo.ps1 -InputFile patrons.csv -LogLevel DEBUG -LogFile run.log -OutputCsv results.csv

.EXAMPLE
    echo "11982021684457" | .\Get-PatronInfo.ps1 -Production
#>
[CmdletBinding()]
param(
    [string]$InputFile,

    [ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')]
    [string]$LogLevel = 'INFO',

    [string]$LogFile,

    [switch]$Production,

    [ValidateRange(1, 64)]
    [int]$ThrottleLimit = 8,

    [ValidateRange(1, 300)]
    [int]$TimeoutSec = 30,

    [ValidateRange(0, 10)]
    [int]$RetryCount = 2,

    [string]$OutputCsv,

    [System.Management.Automation.PSCredential]$Credential,

    # Accepts piped patron-ID lines, e.g. echo "11982021684457" | .\Get-PatronInfo.ps1
    # Declared explicitly (rather than relying on the automatic $input variable)
    # so PowerShell's pipeline parameter binder doesn't emit a non-terminating
    # "input object cannot be bound" error for each piped line.
    [Parameter(ValueFromPipeline = $true)]
    [string]$PatronIdLine
)

begin {
    $ErrorActionPreference = 'Stop'

    $script:LogLevels = @('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')
    $script:LogLevel = $LogLevel

    if ($LogFile) {
        $logDir = Split-Path -Path $LogFile -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
    }
    $script:LogFile = $LogFile

    $script:PipelineLines = [System.Collections.Generic.List[string]]::new()

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    if ($script:LogLevels.IndexOf($Level) -ge $script:LogLevels.IndexOf($script:LogLevel)) {
        $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = "[$ts][$Level] $Message"
        switch ($Level) {
            { $_ -in @('ERROR', 'FATAL') } { Write-Host $line -ForegroundColor Red }
            'WARN'                        { Write-Host $line -ForegroundColor Yellow }
            default                       { Write-Host $line }
        }
        if ($script:LogFile) {
            try {
                Add-Content -Path $script:LogFile -Value $line -ErrorAction Stop
            } catch {
                Write-Host "[$ts][WARN] Failed to write to log file '$($script:LogFile)': $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}

function Get-CarlXServiceUrl {
    param([Parameter(Mandatory)][string]$WsdlPath)
    try {
        [xml]$wsdlXml = Get-Content -Path $WsdlPath -Raw -ErrorAction Stop
    } catch {
        throw "Failed to read/parse WSDL '$WsdlPath': $($_.Exception.Message)"
    }
    $addrNode = $wsdlXml.SelectSingleNode("//*[local-name()='address']")
    if (-not $addrNode -or -not $addrNode.location) {
        throw "Could not find a soap:address/@location in $WsdlPath"
    }
    return $addrNode.location
}

# Posts a SOAP envelope with a timeout, retrying transient failures
# (timeouts, connection resets, non-2xx without a body, etc.) up to
# RetryCount times with a short linear backoff. A response body
# accompanying a non-2xx status (i.e. a SOAP fault) is returned as-is
# rather than retried, since it's a real API response, not a transient
# failure.
function Invoke-CarlXSoapRequest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Envelope,
        [Parameter(Mandatory)][string]$PatronId,
        [int]$TimeoutSec = 30,
        [int]$RetryCount = 2,
        [System.Management.Automation.PSCredential]$Credential
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $params = @{
                Uri             = $Uri
                Method          = 'Post'
                Body            = $Envelope
                ContentType     = 'text/xml; charset=utf-8'
                Headers         = @{ SOAPAction = '""' }
                UseBasicParsing = $true
                TimeoutSec      = $TimeoutSec
            }
            if ($Credential) { $params['Credential'] = $Credential }
            $response = Invoke-WebRequest @params
            Write-Log -Level DEBUG -Message "[$PatronId] HTTP $($response.StatusCode) on attempt $attempt"
            return $response.Content
        } catch {
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                # Non-2xx but with a body - most likely a SOAP fault; treat as
                # a completed (if unhappy) response rather than a failure to retry.
                Write-Log -Level WARN -Message "[$PatronId] Non-success HTTP response with a body on attempt $attempt; treating as a SOAP fault, not retrying."
                return $_.ErrorDetails.Message
            }
            if ($attempt -gt $RetryCount) {
                Write-Log -Level ERROR -Message "[$PatronId] Request failed after $attempt attempt(s): $($_.Exception.Message)"
                throw
            }
            Write-Log -Level WARN -Message "[$PatronId] Attempt $attempt failed ($($_.Exception.Message)); retrying..."
            Start-Sleep -Seconds ([Math]::Min(5, $attempt))
        }
    }
}

# NOTE: kept as a plain string (no here-string) so this function's source
# text can safely be embedded inside the here-string used to ship helper
# functions into ForEach-Object -Parallel runspaces below.
function New-GetPatronInformationEnvelope {
    param([Parameter(Mandatory)][string]$PatronId)
    $escapedId = [System.Security.SecurityElement]::Escape($PatronId)
    return '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><GetPatronInformationRequest xmlns="http://tlcdelivers.com/cx/schemas/patronAPI" xmlns:req="http://tlcdelivers.com/cx/schemas/request"><SearchType>Patron ID</SearchType><SearchID>' + $escapedId + '</SearchID><Modifiers><req:DebugMode>true</req:DebugMode><req:ReportMode>true</req:ReportMode></Modifiers></GetPatronInformationRequest></soap:Body></soap:Envelope>'
}

function ConvertFrom-CarlXPatronResponse {
    param(
        [Parameter(Mandatory)][string]$ResponseXml,
        [string]$PatronId = '?'
    )

    try {
        [xml]$xml = $ResponseXml
    } catch {
        Write-Log -Level ERROR -Message "[$PatronId] Could not parse response as XML: $($_.Exception.Message)"
        throw "Could not parse response XML for patron '$PatronId': $($_.Exception.Message)"
    }

    function Get-LocalText {
        param($Node, [string]$LocalName)
        if (-not $Node) { return $null }
        $n = $Node.SelectSingleNode(".//*[local-name()='$LocalName']")
        if ($n) { return $n.InnerText } else { return $null }
    }

    $patronNode = $xml.SelectSingleNode("//*[local-name()='Patron']")
    $statusNode = $xml.SelectSingleNode("//*[local-name()='ResponseStatus']")
    $faultNode  = $xml.SelectSingleNode("//*[local-name()='Fault']")

    if ($faultNode) {
        Write-Log -Level WARN -Message "[$PatronId] SOAP fault returned: $($faultNode.InnerText)"
    }

    $udf = @{}
    if ($patronNode) {
        foreach ($u in $patronNode.SelectNodes(".//*[local-name()='UserDefinedField']")) {
            $label = Get-LocalText $u 'Label'
            if (-not $label) { $label = Get-LocalText $u 'Name' }
            if ($label) { $udf[$label] = Get-LocalText $u 'Value' }
        }
    }

    $result = [PSCustomObject]@{
        SoapFault             = if ($faultNode) { $faultNode.InnerText } else { $null }
        ResponseStatusCode    = Get-LocalText $statusNode 'Code'
        PatronID              = Get-LocalText $patronNode 'PatronID'
        FullName              = Get-LocalText $patronNode 'FullName'
        DefaultBranch         = Get-LocalText $patronNode 'DefaultBranch'
        PatronStatusCode      = Get-LocalText $patronNode 'PatronStatusCode'
        RegisteredBy          = Get-LocalText $patronNode 'RegisteredBy'
        RegistrationDate      = Get-LocalText $patronNode 'RegistrationDate'
        ExpirationDate        = Get-LocalText $patronNode 'ExpirationDate'
        SendComingDueFlag     = Get-LocalText $patronNode 'SendComingDueFlag'
        CollectionStatus      = Get-LocalText $patronNode 'CollectionStatus'
        SendHoldAvailableFlag = Get-LocalText $patronNode 'SendHoldAvailableFlag'
        SelfServeActivityDate = Get-LocalText $patronNode 'SelfServeActivityDate'
        AddressStreet         = Get-LocalText $patronNode 'Street'
        UserDefinedFields     = $udf
        RawXml                = $ResponseXml
    }

    if ($result.ResponseStatusCode -and $result.ResponseStatusCode -ne '0') {
        Write-Log -Level WARN -Message "[$PatronId] Non-zero ResponseStatusCode: $($result.ResponseStatusCode)"
    }

    return $result
}
} # end begin

process {
    if ($null -ne $PatronIdLine -and $PatronIdLine.Trim() -ne '') {
        $script:PipelineLines.Add($PatronIdLine)
    }
}

end {

$exitCode = 0

try {

    # --- Resolve WSDL / endpoint -------------------------------------------------

    $wsdlFile = if ($Production) {
        Join-Path $PSScriptRoot 'PatronAPI.wsdl'
    } else {
        Join-Path $PSScriptRoot 'PatronAPInew.wsdl'
    }

    Write-Log -Level INFO -Message "wsdlfile: $wsdlFile"

    if (-not (Test-Path $wsdlFile)) {
        throw "WSDL file not found: $wsdlFile"
    }

    $serviceUrl = Get-CarlXServiceUrl -WsdlPath $wsdlFile
    Write-Log -Level INFO -Message "Service endpoint: $serviceUrl"

    # --- Gather patron IDs --------------------------------------------------------

    if ($InputFile) {
        if (-not (Test-Path $InputFile)) { throw "Input file not found: $InputFile" }
        $lines = Get-Content -Path $InputFile
    } elseif ($script:PipelineLines.Count -gt 0) {
        # Populated via PowerShell's own object pipeline, e.g.:
        #   "11982021684457" | & .\Get-PatronInfo.ps1
        $lines = $script:PipelineLines
    } elseif ([Console]::IsInputRedirected) {
        # Populated via OS-level stdin redirection into a separate pwsh.exe process,
        # e.g.: echo "11982021684457" | pwsh -File .\Get-PatronInfo.ps1
        # This does NOT go through PowerShell's ValueFromPipeline binding, so it
        # has to be read directly off the console input stream instead.
        $stdinLines = [System.Collections.Generic.List[string]]::new()
        while ($null -ne ($stdinLine = [Console]::In.ReadLine())) {
            $stdinLines.Add($stdinLine)
        }
        $lines = $stdinLines
    } else {
        throw 'Provide -InputFile <path> or pipe patron ID lines to this script, e.g. echo "11982021684457" | .\Get-PatronInfo.ps1'
    }

    $patronIds = $lines |
        Where-Object { $_ -and $_.ToString().Trim() -ne '' } |
        ForEach-Object { ($_ -split ',')[0].Trim() }

    if ($patronIds.Count -eq 0) {
        Write-Log -Level WARN -Message 'No patron IDs found in input; nothing to do.'
        return
    }

    Write-Log -Level INFO -Message "Processing $($patronIds.Count) patron record(s) with ThrottleLimit=$ThrottleLimit, TimeoutSec=$TimeoutSec, RetryCount=$RetryCount"

    # --- Bundle helper function source so parallel runspaces can use it ---------
    # ForEach-Object -Parallel runs each iteration in its own runspace, which does
    # not inherit functions defined in the caller's scope - only variables passed
    # via $using:. We ship the function *source* in as a string and dot-source it
    # inside each runspace instead.

    $logFuncSrc      = (Get-Content Function:\Write-Log).ToString()
    $requestFuncSrc  = (Get-Content Function:\Invoke-CarlXSoapRequest).ToString()
    $envelopeFuncSrc = (Get-Content Function:\New-GetPatronInformationEnvelope).ToString()
    $parseFuncSrc    = (Get-Content Function:\ConvertFrom-CarlXPatronResponse).ToString()

    $results = $patronIds | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        $patronId   = $_
        $serviceUrl = $using:serviceUrl
        $credential = $using:Credential
        $timeoutSec = $using:TimeoutSec
        $retryCount = $using:RetryCount

        # Recreate logging state (log level/file + the leveled ordering array)
        # in this runspace so the shipped-in Write-Log function behaves the
        # same way it does in the main runspace.
        $script:LogLevels = @('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL')
        $script:LogLevel  = $using:LogLevel
        $script:LogFile   = $using:LogFile

        ${function:Write-Log}                        = [scriptblock]::Create($using:logFuncSrc)
        ${function:Invoke-CarlXSoapRequest}           = [scriptblock]::Create($using:requestFuncSrc)
        ${function:New-GetPatronInformationEnvelope}  = [scriptblock]::Create($using:envelopeFuncSrc)
        ${function:ConvertFrom-CarlXPatronResponse}   = [scriptblock]::Create($using:parseFuncSrc)

        try {
            Write-Log -Level DEBUG -Message "[$patronId] Building request"
            $envelope = New-GetPatronInformationEnvelope -PatronId $patronId

            $responseText = Invoke-CarlXSoapRequest -Uri $serviceUrl -Envelope $envelope -PatronId $patronId `
                -TimeoutSec $timeoutSec -RetryCount $retryCount -Credential $credential

            $parsed = ConvertFrom-CarlXPatronResponse -ResponseXml $responseText -PatronId $patronId
            $parsed | Add-Member -NotePropertyName SearchID -NotePropertyValue $patronId -PassThru
        } catch {
            Write-Log -Level ERROR -Message "[$patronId] Lookup failed: $($_.Exception.Message)"
            [PSCustomObject]@{
                SearchID = $patronId
                Error    = $_.Exception.Message
            }
        }
    }

    # --- Report / export ----------------------------------------------------------

    $results | Select-Object SearchID, ResponseStatusCode, PatronID, FullName, DefaultBranch, PatronStatusCode, Error |
        Format-Table -AutoSize

    $failedCount = ($results | Where-Object { $_.Error -or $_.SoapFault -or ($_.ResponseStatusCode -and $_.ResponseStatusCode -ne '0') }).Count
    $succeededCount = $results.Count - $failedCount
    Write-Log -Level INFO -Message "Completed: $($results.Count) total, $succeededCount succeeded, $failedCount failed/faulted."
    if ($failedCount -gt 0) { $exitCode = 1 }

    if ($OutputCsv) {
        try {
            $results | Select-Object * -ExcludeProperty RawXml, UserDefinedFields |
                Export-Csv -Path $OutputCsv -NoTypeInformation -ErrorAction Stop
            Write-Log -Level INFO -Message "Results written to $OutputCsv"
        } catch {
            Write-Log -Level ERROR -Message "Failed to write results to '$OutputCsv': $($_.Exception.Message)"
            $exitCode = 1
        }
    }

} catch {
    Write-Log -Level FATAL -Message "Unhandled error: $($_.Exception.Message)"
    Write-Log -Level DEBUG -Message "$($_.ScriptStackTrace)"
    $exitCode = 1
} finally {
    exit $exitCode
}

} # end end
