# Report-UserSignIns.PS1
# Report user sign ins with information about what apps are used based on what is available in the Entra Audit Sign-in Log

# V1.0 5-Nov-2024
# GitHub link: https://github.com/12Knocksinna/Office365itpros/blob/master/Report-UserSignIns.PS1

Write-Host "Checking connections..."
$Modules = Get-Module | Select-Object -ExpandProperty Name
If ('ExchangeOnlineManagement' -notin $Modules) {
    Write-Host "Connecting to Exchange Online..."
    Connect-ExchangeOnline -SkipLoadingCmdletHelp -ShowBanner:$false
}       
If (!(Get-MgContext).Account) {
    Write-Host "Connecting to Microsoft Graph..."
    Connect-MgGraph -NoWelcome -Scopes Directory.Read.All, AuditLog.Read.All
}

Write-Host "Starting up..."
# Find Exchange shared and room mailboxes so that we can remove them from any user account reporting
[array]$SharedMailboxes = Get-ExoMailbox -RecipientTypeDetails SharedMailbox, RoomMailbox -ResultSize Unlimited
If ($SharedMailboxes) {
    $SharedMailboxHash = @{}
    ForEach ($SMbx in $SharedMailboxes) {
        $SharedMailboxHash.Add($SMbx.ExternalDirectoryObjectId, $SMbx.DisplayName)
    }
}

$AppDataAvailable = $false
$AppDataFile = 'C:\temp\AppInfo.csv'
If (Test-path $AppDataFile) {
    $AppDataAvailable = $true
    [array]$AppDataInfo = Import-CSV $AppDataFile
    $AppDataHash = @{}
    ForEach ($App in $AppDataInfo) {
        $AppDataHash.Add($App.App, $App.Name)
    }
}   

# Find User accounts to process
[array]$Users = Get-MgUser -Filter "assignedLicenses/`$count ne 0 and userType eq 'Member'" -PageSize 500 `
    -Property Id, displayName, userPrincipalName, userType, assignedLicenses, signInActivity `
    -ConsistencyLevel eventual -CountVariable Count -Sort 'displayName ASC'
If ($Users) {
    Write-Host  ("{0} users found" -f $Users.Count)
} Else {
    Write-Host "Some problem occurred finding users. None found to process. Exiting..." 
    Break
}

$Report = [System.Collections.Generic.List[Object]]::new()
[int]$i = 0
ForEach ($User in $Users) {
    If ($SharedMailboxHash[$User.Id]) {
    # Ignore non-user mailboxes that happen to have a license
        Continue
    }
    $i++
    $LastSignIn = $null
    Write-Host ("Processing account {0} ({1}/{2})" -f $User.DisplayName, $i, $Users.Count)
    # Get the last sign in date for the user
    If ($User.SignInActivity.LastSuccessfulSignInDateTime) {
        $LastSignIn = $User.SignInActivity.LastSuccessfulSignInDateTime 
    } Else {
        $LastSignIn = $User.SignInactivity.LastSignInDateTime
    }
    If ($null -eq $LastSignIn) {
        $LastSignIn = "Never"
        $DaysSinceSignIn = "N/A"
    } Else {
        # Is it less than 30 days since a sign-in?
        [array]$AppNames = $null
        $LastSignIn = Get-Date $LastSignIn -format 'dd-MMM-yyyy HH:mm:ss'
        $DaysSinceSignIn = (New-TimeSpan ($LastSignIn)).Days
        If ($DaysSinceSignIn -lt 30) {
            # We can search audit logs to find out what apps the user has used
            $UserId = $User.Id
            [array]$AuditSignIns = Get-MgAuditLogSignIn -Filter "userId eq '$UserId'" -Top 50
            # If we are using a custom app name list, we need to look up each app name
            If ($AuditSignIns.count -eq 0) {
                $AppNames = "No sign-ins"
            }
            If ($AppDataAvailable) {
                [array]$UserApps = $AuditSignIns.AppId | Select-Object -Unique
                ForEach ($UserApp in $UserApps) {
                    $UserAppName = $AppDataHash[$UserApp]
                    If ($UserAppName) {
                        $AppNames += $UserAppName
                    } Else {
                        $AppNames += "Unknown app"
                    }
                }
            } Else {
                [array]$Apps = $AuditSignIns.AppDisplayName | Select-Object -Unique
                $AppNames = $Apps.AppDisplayName
            }
        } Else {
            $AppNames = "N/A"
        }
    }
    # Handle the situation where the audit logs don't have any non-interactive sign-ins (use the beta cmdlet if you want to include these)
    If (!($Apps)) {
        $AppNames = "non-interactive apps"
    }

    $ReportLine = [PSCustomObject]@{
        UserPrincipalName       = $User.UserPrincipalName
        User                    = $User.DisplayName
        'Last sign in'          = $LastSignIn
        'Days since sign in'    = $DaysSinceSignIn
        'Apps used'             = $AppNames -join ", "
    }
    $Report.Add($ReportLine)
}

# Output what we found
$Report = $Report | Sort-Object {$_.'Last sign in' -as [datetime]} -Descending 
$Report | Out-GridView -Title "User Sign-ins"

Write-Host "Generating report..."
If (Get-Module ImportExcel -ListAvailable) {
    $ExcelGenerated = $True
    Import-Module ImportExcel -ErrorAction SilentlyContinue
    $ExcelOutputFile = ((New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path) + "\User SignIn Report.xlsx"
    If (Test-Path $ExcelOutputFile) {
        Remove-Item $ExcelOutputFile -ErrorAction SilentlyContinue
    }
    $Report | Export-Excel -Path $ExcelOutputFile -WorksheetName "User Sign In Report" -Title ("User Sign In Report {0}" -f (Get-Date -format 'dd-MMM-yyyy')) -TitleBold -TableName "UserSignIns" 
   
} Else {
    $CSVOutputFile = ((New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path) + "\User SignIn Report.CSV"
    $Report | Export-Csv -Path $CSVOutputFile -NoTypeInformation -Encoding Utf8
}
 
If ($ExcelGenerated) {
    Write-Host ("An Excel report is available in {0}" -f $ExcelOutputFile)
} Else {    
    Write-Host ("A CSV report is available in {0}" -f $CSVOutputFile)
}  

# An example script used to illustrate a concept. More information about the topic can be found in the Office 365 for IT Pros eBook https://gum.co/O365IT/
# and/or a relevant article on https://office365itpros.com or https://www.practical365.com. See our post about the Office 365 for IT Pros repository # https://office365itpros.com/office-365-github-repository/ for information about the scripts we write.

# Do not use our scripts in production until you are satisfied that the code meets the need of your organization. Never run any code downloaded from the Internet without
# first validating the code in a non-production environment.