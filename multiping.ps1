<#
.SYNOPSIS
   <A brief description of the script>
.DESCRIPTION
   <A detailed description of the script>
.PARAMETER <paramName>
   <Description of script parameter>
.EXAMPLE
   <An example of using the script>
#>
param([string]$fileName = $( `
		Throw "Parameter missing Please provide filename"))
if (!(Test-Path $fileName)) {Throw "The file - $fileName does not exist in the current directory"}
[array]$multiIP = Get-Content $fileName

$timeout = 2 * 1000
$history = [string[]]::new($multiIP.Count)
$maxtimeout = [timespan[]]::new($multiIP.Count)
$timeoutcount = [int[]]::new($multiIP.Count)
$curtimeout = [bool[]]::new($multiIP.Count)
$timeout_seconds = [timespan[]]::new($multiIP.Count)
$timeout_start = [datetime[]]::new($multiIP.Count)
$longest_timeout_start = [datetime[]]::new($multiIP.Count)
$longest_timeout_start = @(0) * ($multiIP.Count)
$min = [int[]]::new($multiIP.Count)
$min = @($timeout) * ($multiIP.Count)
$max = [int[]]::new($multiIP.Count)
$avg = [double[]]::new($multiIP.Count)
$drops = [int[]]::new($multiIP.Count)
$prevStatus = [string[]]::new($multiIP.Count)
$auditTrail = [string[]]::new($multiIP.Count)
[long]$n = 1
[int]$buckets = 20
[int]$interval = 5000
[int]$timeouts = 0
$outagewindow = 8

<#
if($interval -lt 1)
	{Throw "interval must an integer greater or equal to 1"}
#>
[string]$displayunit = "ms"

while ($true)
	{
	[int]$i = 0
	[int]$invalid_ping=0
	Write-Output("")
	$Tasks = @(foreach ($ip in $multiIP)
		{
		$ip=$ip.trim()
		if ($ip.StartsWith("#")) { continue }
		(New-Object System.Net.NetworkInformation.Ping).SendPingAsync($ip,$timeout)
		})
	if ($Tasks.Count -gt 0) { [Threading.Tasks.Task]::WaitAll($Tasks) }
	Clear-Host
	Write-Output("{0,-15}   {1,5} {2,7} {3,11} {4,-20} {5,5} {6,8} {7,8} {8,8}" -f "IP Address", "State", "RTT", "Min/Avg/Max", "History", "Drops", "Timeout", "Max T/O", "Since")
	[int]$t = 0
	foreach ($loopIp in $multiIP)
		{
		$loopIp = $loopIp.trim()
		if ($loopIp.StartsWith("#"))
			{
			Write-Output $loopIp
			$i++
			$invalid_ping++
			continue
			}
		$Response = $Tasks[$t].Result
		if ($Response.Status -match "Success")
			{
			[string]$result = "Up"
			[string]$tick = "!"
			$curtimeout[$i] = $false
			}
		elseif ($Response.Status -match "TimedOut")
			{
			[string]$result = "Down"
			[string]$tick = "."
			$curtimeout[$i] = $true
			$drops[$i]++
			}
		elseif ($Response.Status -match "DestinationHostUnreachable")
			{
			[string]$result = "DHUr"
			[string]$tick = "U"
			$curtimeout[$i] = $false
			}
		elseif ($Response.Status -match "NoResources")
			{
			[string]$result = "NoRe"
			[string]$tick = "?"
			$curtimeout[$i] = $false
			}
		elseif ($Response.Status -match "TtlExpired")
			{
			[string]$result = "TTL"
			[string]$tick = "E"
			$curtimeout[$i] = $false
			}
		elseif ($Response.Status -match "DestinationNetworkUnreachable")
			{
			[string]$result = "DNUr"
			[string]$tick = "U"
			$curtimeout[$i] = $false
			}
		else
			{
			Write-Output("Result is undefined - ")
			Write-Output($Response.Status)
			exit
			}

		if ([string]::IsNullOrEmpty($prevStatus[$i]))
			{
			$prevStatus[$i] = $result
			}
		elseif ($prevStatus[$i] -ne $result)
			{
			if ($result -eq "Up" -or $result -eq "Down") { Write-Host -NoNewLine "`a" }
			$auditTrail[$i] = "{0,-15} changed to {1,4} at {2:HH:mm:ss}" -f $multiIP[$i], $result, (Get-Date)
			$prevStatus[$i] = $result
			}

		if ($history[$i].length -lt $buckets)
			{
			$history[$i] = $tick + $history[$i]
			}
		else
			{
			$history[$i] = $tick + $history[$i].Substring(0,$buckets-1)
			}
		if ($curtimeout[$i])
			{
			$timeoutcount[$i]++
			$timestamp = Get-Date
			if($timeoutcount[$i] -eq 1)
				{
				$timeout_start[$i] = $timestamp.AddMilliseconds(-$timeout)
				}
			$timeout_seconds[$i] = New-TimeSpan -Start $timeout_start[$i] -End $timestamp
			}
		else
			{
			$timeoutcount[$i] = 0
			$timeout_seconds[$i] = 0
			} 
		if ($timeout_seconds[$i] -gt $maxtimeout[$i])
			{
			$maxtimeout[$i] = $timeout_seconds[$i]
			$longest_timeout_start[$i] = $timeout_start[$i]
			}
		if ($maxtimeout[$i].Totalminutes -ge $outagewindow)
			{
			$hl = "*"
			}
		else
			{
			$hl=""
			}
		if ($Response.RoundtripTime -lt $min[$i] -and $Response.RoundtripTime -ne 0)
			{
			$min[$i] = $Response.RoundtripTime
			}
		if ($Response.RoundtripTime -gt $max[$i])
			{
			$max[$i] = $Response.RoundtripTime
			}
		[double]$a = 1/$n
		[double]$b = 1 - $a
		if($Response.RoundtripTime -eq 0)
			{
			$rtt = $max[$i]
			}
		else
			{
			$rtt = $Response.RoundtripTime
			}
		$avg[$i] = $a * $rtt + $b * $avg[$i]
		$stats = $min[$i].ToString() + '/' + [int]$avg[$i].ToString() + '/' + $max[$i].ToString()
		
		Write-Output("{0,-15}{1,3}{2,5} {3,5}ms {4,11} {5,-20} {6,5} {7:hh\:mm\:ss} {8:hh\:mm\:ss} {9:HH\:mm\:ss}{10,1}" -f $multiIP[$i],"is",$result,$Response.RoundtripTime,$stats,$history[$i],$drops[$i],$timeout_seconds[$i],$maxtimeout[$i],$longest_timeout_start[$i],$hl)	
		$i++
		$t++
		}
	$timeout_quantity = ($curtimeout | Measure-Object -Sum).Sum
	
	$auditCount = ($auditTrail | Where-Object { ![string]::IsNullOrEmpty($_) }).Count
	if ($auditCount -gt 0)
		{
		Write-Output("")
		Write-Output("--- Audit Trail ---")
		$sortedAudits = $auditTrail | Where-Object { ![string]::IsNullOrEmpty($_) } | Sort-Object { $_.Substring($_.Length - 8) }
		foreach ($audit in $sortedAudits)
			{
			Write-Output $audit
			}
		}

	Write-Output("")
	Write-Output("{0,23} Pause {1}{2} for {3}/{4} host failures" -f (get-date),$interval,$displayunit,$timeout_quantity,($multiIP.Count - $invalid_ping))
	$n++
	Start-Sleep -Milliseconds $interval
	}

# SIG # Begin signature block
# MIID+QYJKoZIhvcNAQcCoIID6jCCA+YCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUrmO5s9ySN9YuYOrSa/2RgC8G
# RZugggIWMIICEjCCAX+gAwIBAgIQRAvXN5hVOKdPdH0nVjN4hDAJBgUrDgMCHQUA
# MBkxFzAVBgNVBAMTDlBhdHJpY2sgQmFybmVzMB4XDTE2MDcyMjE0MjEyM1oXDTM5
# MTIzMTIzNTk1OVowGTEXMBUGA1UEAxMOUGF0cmljayBCYXJuZXMwgZ8wDQYJKoZI
# hvcNAQEBBQADgY0AMIGJAoGBAJYUs/VxuHE2TAcpDD+p3qEmNz3xSaa7g6QOMags
# ySY6ai/O+E6h+0bTLwYWMjJeHsQvd9v4IkiUwKwxSX5j4bvBSGQhYH9bZm3kUgZ0
# y0ZHpn3LGSNzkf/A7paKD7m0jsR9AAa+GxMbkegQFkKUH8kDQ/f1VzUeFXU2+zCU
# BOO/AgMBAAGjYzBhMBMGA1UdJQQMMAoGCCsGAQUFBwMDMEoGA1UdAQRDMEGAEEoH
# CqL/Uozgcg8oNjkA14ahGzAZMRcwFQYDVQQDEw5QYXRyaWNrIEJhcm5lc4IQRAvX
# N5hVOKdPdH0nVjN4hDAJBgUrDgMCHQUAA4GBAE5aURIW8TCEik3Mt80YjwiqG4Xc
# gZ6NtR103QqMj3XDSYjQbMXHw3vyQit53VTKCyyBFpuoSJuJMyjFnxwAukYnx+KG
# W9LFQ0f6Fvg38y8BqXdKXljhXHRWD7SDExvAKZFLo9CuE+xuYgHy6fNfj3dW2+4J
# cA0xnw1u1k0mNkscMYIBTTCCAUkCAQEwLTAZMRcwFQYDVQQDEw5QYXRyaWNrIEJh
# cm5lcwIQRAvXN5hVOKdPdH0nVjN4hDAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIB
# DDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEE
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUk1XHtAz5brm2
# yeKpNuWPcpT8iPAwDQYJKoZIhvcNAQEBBQAEgYA50BLFCzKZygIyYz6Z/LZcDUtG
# soHYjv9T/igS01tDjjerXwEZKsbSH78602AOTBCXJBFxpPqAOTKe1Kj5g/zZaNA0
# 5SivAJCemeie7ne5b7jaOeQ/WHiXjhBYBDZIKNf1MOJ9C9KcgjrUmKfbNgb2GVQV
# o4ARyMnKVg1FP6dLAA==
# SIG # End signature block
