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

Install-Module Microsoft.PowerShell.SecretManagement
Install-Module Microsoft.PowerShell.SecretStore

Import-Module Microsoft.PowerShell.SecretManagement
Import-Module Microsoft.PowerShell.SecretStore

# This should only be run on the template vm
$computerName = (Get-WmiObject Win32_ComputerSystem).Name
Write-LogFile "Check VM name section."
if (!($computerName.StartsWith('lab000'))) {
    
    Write-LogFile "Renaming the computer '$env:COMPUTERNAME' to 'lab000001'"
    Rename-Computer -ComputerName $env:COMPUTERNAME -NewName "lab000001" -Force
    Write-LogFile "Local Computer name will be changed to 'lab000001' -- after restarting the vm."
    Restart-Computer -Force    
}

# Password path
$passwordPath = Join-Path $($env:Userprofile) SecretStore.vault.credential

# if password file exists try to login with that
if (!(Test-Path $passwordPath)) {
    $pass = Read-Host -AsSecureString -Prompt 'Enter the extension vault password'
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
$djUser = Read-Host -AsSecureString -Prompt 'Enter user to domain join.'
Set-Secret -Name DomainJoinUser -Secret $djUser

$djPass = Read-Host -AsSecureString -Prompt 'Enter password to domain join.'
Set-Secret -Name DomainJoinPassword -Secret $djPass

$djName = Read-Host -AsSecureString -Prompt 'Enter domain join.'
Set-Secret -Name DomainName -Secret $djName

$aadGroupName = Read-Host -AsSecureString -Prompt 'Enter AAD Group name.'
Set-Secret -Name AADGroupName -Secret $aadGroupName

$labId = Read-Host -AsSecureString -Prompt 'Enter 7 char lab id.'
Set-Secret -Name LabId -Secret $labId

# Copy down files into the Public documents folder
Invoke-WebRequest -Uri https://raw.githubusercontent.com/Azure/LabServices/domainjoinv2/TemplateManagement/PowerShell/ActiveDirectoryJoinV2/DomainJoin.ps1 -OutFile C:\Users\Public\Documents\DomainJoin.ps1

$testTask = Get-ScheduledTask -TaskName DomainJoinTask

if (!$testTask) {
    # Setup task scheduler
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File DomainJoin.ps1" -WorkingDirectory "C:\Users\Public\Documents"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "$($env:USERDOMAIN)\$($env:USERNAME)" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -DisallowDemandStart -Hidden
    $task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settings -Description "Domain join task for Lab Service VM"
    Register-ScheduledTask DomainJoinTask -InputObject $task
}
Read-Host -Prompt 'Update the scheduled task to add the user password.'
# TODO edit the task in the scheduler and add the password interactively.