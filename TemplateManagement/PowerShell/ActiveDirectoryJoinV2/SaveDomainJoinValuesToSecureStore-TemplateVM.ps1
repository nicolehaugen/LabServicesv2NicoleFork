<#
The MIT License (MIT)
Copyright (c) Microsoft Corporation  
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
.SYNOPSIS
This script is part of the scripts chain for joining a student VM to an Active Directory domain. It renames the computer with a unique ID. Then it schedules the actual join script to run after reboot.
.LINK https://docs.microsoft.com/en-us/azure/lab-services/classroom-labs/how-to-connect-peer-virtual-network
#>


[CmdletBinding()]
param()

###################################################################################################

function Write-LogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )
 
    # Get the current date
    $TimeStamp = Get-Date -Format o

    # Add Content to the Log File
    $Line = "$TimeStamp - $Message"
    Add-content -Path $Logfile -Value $Line -ErrorAction SilentlyContinue
    Write-Output $Line
}


Import-Module Microsoft.PowerShell.SecretManagement
Import-Module Microsoft.PowerShell.SecretStore

$LogFile = Join-Path $($env:Userprofile) "DJLog$(Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }).txt"
New-Item -Path $logFile -ItemType File

# Password path
$passwordPath = Join-Path $($env:Userprofile) SecretStore.vault.credential

# if password file exists try to login with that
if (!(Test-Path $passwordPath)) {
    $pass = Read-Host -AsSecureString -Prompt 'Enter the secretstore vault password'
    # Uses the DPAPI to encrypt the password
    $pass | Export-CliXml $passwordPath 
     
}

$pass = Import-CliXml $passwordPath
# Check if store configuration exists
$gssc = Get-SecretStoreConfiguration

if (!$gssc) {

    # if not create one
    Set-SecretStoreConfiguration -Scope CurrentUser -Authentication Password -PasswordTimeout (60*60) -Interaction None -Password $pass -Confirm:$false
    
    Register-SecretVault -Name SecretStore -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
 
}

Unlock-SecretStore -Password $pass

# Set Secrets
$djUser = Read-Host -AsSecureString -Prompt 'Enter user name to domain join (ie .\admin).'
Set-Secret -Name DomainJoinUser -Secret $djUser

$djPass = Read-Host -AsSecureString -Prompt 'Enter password to domain join.'
Set-Secret -Name DomainJoinPassword -Secret $djPass

$djName = Read-Host -AsSecureString -Prompt 'Enter the domain join. (ie contoso.com)'
Set-Secret -Name DomainName -Secret $djName

$aadGroupName = Read-Host -AsSecureString -Prompt 'Enter the Lab AAD Group name.'
Set-Secret -Name AADGroupName -Secret $aadGroupName

$labId = Read-Host -AsSecureString -Prompt 'Enter 5 character lab id prefix. (ie Alpha)'
Set-Secret -Name LabId -Secret $labId

Set-Secret -Name TemplateIP -Secret $((Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin DHCP).IPAddress)

# Copy down files into the Public documents folder
# TODO set the correct final location
Invoke-WebRequest -Uri https://raw.githubusercontent.com/Azure/LabServices/domainjoinv2/TemplateManagement/PowerShell/ActiveDirectoryJoinV2/DomainJoin.ps1 -OutFile C:\Users\Public\Documents\DomainJoin.ps1

# Section to automatically create scheduled task
# $testTask = Get-ScheduledTask -TaskName DomainJoinTask -ErrorAction SilentlyContinue

# if (!$testTask) {
#     # Setup task scheduler
#     $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File DomainJoin.ps1" -WorkingDirectory "C:\Users\Public\Documents"
#     $trigger = New-ScheduledTaskTrigger -AtStartup
#     $principal = New-ScheduledTaskPrincipal -UserId "$($env:USERDOMAIN)\$($env:USERNAME)" -RunLevel Highest -LogonType Password
#     $settings = New-ScheduledTaskSettingsSet -DisallowDemandStart -Hidden
#     $task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settings -Description "Domain join task for Lab Service VM"
#     $SecurePassword = Read-Host -Prompt 'Enter user password to register the task' -AsSecureString
#     $UserName = "$env:USERNAME"
#     $Credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $UserName, $SecurePassword
#     $Password = $Credentials.GetNetworkCredential().Password 
#     Register-ScheduledTask DomainJoinTask -InputObject $task -Password $Password -User "$env:USERNAME" -Force
# }