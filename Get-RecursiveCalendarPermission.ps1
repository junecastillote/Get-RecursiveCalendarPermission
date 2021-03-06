
<#PSScriptInfo

.VERSION 1.0

.GUID 0605001e-1e62-4bf8-8de9-33cff02561c3

.AUTHOR June Castillote

.COMPANYNAME www.lazyexchangeadmin.com

.COPYRIGHT june.castillote@gmail.com

.TAGS 

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES


#>

<#
.DESCRIPTION
This script can be used to Export the list of exchange mailbox calendar permission 

.SYNOPSIS
Export the list of exchange mailbox calendar permission 

.PARAMETER mailboxList
The list of mailboxes to be reported. Can be provided using an array ("mailbox1","mailbox2"), or the (Get-Mailbox).UserPrincipal command, or from a text file (get-content mailboxes.txt)

.PARAMETER reportFile
The Path of the CSV file where the results will be exported to.

.PARAMETER logFile
The path of the transcript log file. If not specified, transcript logging will not run.

.EXAMPLE
$mailboxes = "User1","User2"; Get-RecursiveCalendarPermission.ps1 -mailboxList $mailboxes -reportFile .\calendar_permissions.csv

.EXAMPLE
$mailboxes = (Get-Mailbox -ResultSize Unlimited).PrimarySMTPAddress; Get-RecursiveCalendarPermission.ps1 -mailboxList$mailboxes -reportFile .\calendar_permissions.csv

.EXAMPLE
$mailboxes = (Get-Mailbox User1).PrimarySMTPAddress; Get-RecursiveCalendarPermission.ps1 -mailboxList$mailboxes -reportFile .\calendar_permissions.csv

.EXAMPLE
Get-RecursiveCalendarPermission.ps1 -mailboxList (Get-Mailbox -ResultSize 100).PrimarySMTPAddress -reportFile .\calendar_permissions.csv

.EXAMPLE
Get-RecursiveCalendarPermission.ps1 -mailboxList (Get-Mailbox User1).PrimarySMTPAddress -reportFile .\calendar_permissions.csv

.EXAMPLE
$mailboxes = Get-Content .\mailboxList.txt; Get-RecursiveCalendarPermission.ps1 -mailboxList $mailboxes -reportFile .\calendar_permissions.csv

.EXAMPLE
Get-RecursiveCalendarPermission.ps1 -mailboxList (Get-Content .\mailboxList.txt) -reportFile .\calendar_permissions.csv

.NOTES
june.castillote@gmail.com
#>
[CmdletBinding()]
param(
	[parameter(mandatory=$true)]
	[string[]]$mailboxList,
	[parameter(mandatory=$false)]
	[string]$logFile,
	[parameter(mandatory=$true)]
	[string]$reportFile
)

Function Stop-TxnLogging
{
	$txnLog=""
	Do {
		try {
			Stop-Transcript | Out-Null
		} 
		catch [System.InvalidOperationException]{
			$txnLog="stopped"
		}
    } While ($txnLog -ne "stopped")
}

Function Start-TxnLogging {
    param (
    [Parameter(Mandatory=$true)]
    [string]$logPath
    )
	Stop-TxnLogging
    Start-Transcript $logPath -Append
}

#Function to recursively list group members (nested)
Function Get-MembersRecursive ($groupName)
{
    $groupMembers = @()
    $groupName = Get-Group $groupName -ErrorAction SilentlyContinue
    foreach ($groupMember in $groupName.Members)
    {
        if (Get-Group $groupMember -ErrorAction SilentlyContinue)
        {
            $groupMembers += Get-MembersRecursive $groupMember
        }
        else {
			$groupMembers += get-user $groupMember.Name -ErrorAction SilentlyContinue
        }
    }
    $groupMembers = $groupMembers | Select-Object -Unique
    return $groupMembers
}

if ($logFile) {Start-TxnLogging -logPath $logFile}

Write-Host "Total Number of Mailbox to Process: $($mailboxList.count)" -ForegroundColor Green
$i = 1
$finalReport = @()
foreach ($mailbox in $mailboxList)
{

Write-Host "Mailbox [$($i) of $($mailboxList.count)] : $($mailbox)" -ForegroundColor Yellow
$mailboxFolderPermissions = Get-MailboxFolderPermission "$($mailbox):\Calendar" | Where-Object {$_.user.tostring() -ne "NT AUTHORITY\SELF" -and $_.user.tostring() -ne "Default" -and $_.user.tostring() -ne "Anonymous"}
$mailboxDetail = Get-Recipient $mailbox
	if ($mailboxFolderPermissions.count -gt 0)
	{
		#Write-Host "Access List: " -ForegroundColor Cyan
		foreach ($mailboxFolderPermission in $mailboxFolderPermissions)
		{	
			$userObj = Get-User $mailboxFolderPermission.User.ToString() -ErrorAction SilentlyContinue
			if (!$userObj) {
				$groupObj = Get-Group $mailboxFolderPermission.User.ToString() -ErrorAction SilentlyContinue
			}
			$recipientObj = Get-Recipient $mailboxFolderPermission.User.ToString() -ErrorAction SilentlyContinue			
			
			#if the UserName is a group, recursively extract members
			if ($recipientObj -and $recipientObj.RecipientType -match 'group')
			{
				#Call function to recurse the group
				$members = Get-MembersRecursive $recipientObj.Identity						
				
				#if the function returned a non ZERO result
				if ($members.count -gt 0)
				{
					#Write-Host "Access List: " -ForegroundColor Cyan -NoNewLine
					foreach ($member in $members)
					{
						Write-Host "     $($member.UserPrincipalName)" -ForegroundColor Cyan
						$temp = "" | Select-Object MailboxSamAccountName,MailboxEmailAddress,UserSamAccountName,UserEmailAddress,AccessRights,MailboxName,UserPrincipalName,UserName,AccessType,ParentGroupName,ParentGroupEmailAddress,UserAccountControl
						$memberObj = Get-Recipient $member.Identity	-ErrorAction SilentlyContinue
						$temp.MailboxSamAccountName = $mailboxDetail.SamAccountName
						$temp.MailboxName = $mailboxDetail.Name
						$temp.MailboxEmailAddress = $mailboxDetail.PrimarySMTPAddress
						$temp.UserName = $member.Name
						$temp.UserSamAccountName = $member.SamAccountName
						$temp.UserPrincipalName = $member.UserPrincipalName
						$temp.UserEmailAddress = $memberObj.PrimarySMTPAddress
						$temp.ParentGroupName = $groupObj.DisplayName
						$temp.ParentGroupEmailAddress = $groupObj.WindowsEmailAddress
						$temp.AccessType = "Group Access"
						$temp.AccessRights = ($mailboxFolderPermission.AccessRights -join (","))						
						$temp.UserAccountControl = $member.UserAccountControl
						$finalReport += $temp
					}				
				}				
			}
			else
			{	
				if (!$recipientObj -and $userObj) {
					Write-Host "     $($userObj.UserPrincipalName)" -ForegroundColor Cyan
				}
				elseif (!$userObj -and $recipientObj) {
					Write-Host "     $($recipientObj.PrimarySMTPAddress)" -ForegroundColor Cyan
				}
				elseif ($userObj -and $recipientObj) {
					Write-Host "     $($recipientObj.PrimarySMTPAddress)" -ForegroundColor Cyan
				}
								
				if ($recipientObj) {
					$temp = "" | Select-Object MailboxSamAccountName,MailboxEmailAddress,UserSamAccountName,UserEmailAddress,AccessRights,MailboxName,UserPrincipalName,UserName,AccessType,ParentGroupName,ParentGroupEmailAddress,UserAccountControl
					$temp.MailboxSamAccountName = $mailboxDetail.SamAccountName
					$temp.MailboxName = $mailboxDetail.Name
					$temp.MailboxEmailAddress = $mailboxDetail.PrimarySMTPAddress
					$temp.UserName = $mailboxFolderPermission.User.ToString().Split("\")[-1]
					$temp.UserSamAccountName = $userObj.SamAccountName
					$temp.UserPrincipalName = $userObj.UserPrincipalName
					$temp.UserEmailAddress = $recipientObj.PrimarySMTPAddress
					$temp.AccessType = "Direct User Access"
					$temp.AccessRights = ($mailboxFolderPermission.AccessRights -join (","))
					$temp.ParentGroupName = "NONE"
					$temp.ParentGroupEmailAddress = "NONE"
					$temp.UserAccountControl = $userObj.UserAccountControl
					$finalReport += $temp
				}
				
			}	
		}
	}
$i++
}
$finalReport | export-csv -NoTypeInformation $reportFile
Write-Host "Process Completed." -ForegroundColor Green
Stop-TxnLogging