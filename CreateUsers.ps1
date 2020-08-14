$displayNamePrefix = "Test User "
$groupName = "Varonis Assignment Group"
$countFrom = 1
$createCount = 20
$approvedUPN = "peretztestrickett.onmicrosoft.com"  # Domain must be verified for use with the Azure account for a valid UserPrincipalName
$defaultPassword = "G4rfunkl3!"
$magicRetryConstant = 300

$mailNamePrefix = $displayNamePrefix -replace '\s',''
$timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
$logFile = "${PWD}\user_creation_${timestamp}.log"

Write-Host "Create password profile for user creation"
$userPasswordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
$userPasswordProfile.Password = $defaultPassword
$userPasswordProfile.ForceChangePasswordNextLogin = $true
$userPasswordProfile.EnforceChangePasswordPolicy = $true

Write-Host "Create set of users to be created with validation bits"
$userList = New-Object -TypeName "System.Collections.ArrayList"
for ($i = $countFrom; $i -le $createCount; $i++) {
    $user = @{
        groupSuccess = $false
        createSuccess = $false
        displayName = "${displayNamePrefix}${i}"
        mailNickName = "${mailNamePrefix}${i}"
        userPrincipalName = "${mailNamePrefix}${i}@${approvedUPN}"
        azUser = $null
    }
    $user
    [void]$userList.Add($user)
    Write-Host "Added $($user.displayName) to the list"
}

Write-Host "Process the user account creation on Azure"
foreach ($user in $userList) {
    $user.azUser = New-AzureADUser `
        -DisplayName $user.displayName `
        -MailNickName $user.mailNickName `
        -UserPrincipalName $user.userPrincipalName `
        -AccountEnabled $false `
        -PasswordProfile $userPasswordProfile
    $user
    if ($null -ne $user.azUser) {
        $user.createSuccess = $true
        Write-Host "Azure user created for $($user.displayName)"
    }
}

Write-Host "Create Azure AD group ${groupName}"
$azGroup = New-AzureADGroup `
    -DisplayName $groupName `
    -MailEnabled $false `
    -SecurityEnabled $true `
    -MailNickName "NotSet"
$azGroup
if ($null -ne $azGroup) {
    Write-Host "${groupName} successfully created"
} else {
    Write-Host "${groupName} failed to create"
}

Write-Host "Add the user set to the AD group ${groupName}"
$secondsToWait = 0
$allUsersAdded = ($userList | Where-Object { !$_.groupSuccess }).count -eq 0
do {
    if ($secondsToWait -eq 0) {
        $secondsToWait += $magicRetryConstant
    } else {
        $secondsToWait += $secondsToWait + $magicRetryConstant
        Write-Host "Will retry in ${secondsToWait} seconds"
        Start-Sleep -Seconds $secondsToWait
    }

    foreach ($user in $userList) {
        if ($user.groupSuccess) { continue }
    
        $timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
        $result = "FAIL"
        try {
            [string]$foo = $azGroup.ObjectId.ToString()
            $foo = $foo.Replace('e', 'B')
            Add-AzureADGroupMember -ObjectId $azGroup.ObjectId -RefObjectId $user.azUser.ObjectId         #$foo -RefObjectId $user.azUser.ObjectId
            $user.groupSuccess = $true
            $result = "SUCCESS"
        }
        catch { }
    
        $logMessage = "${timestamp}`t$($user.userPrincipalName)`t${result}"
        Add-Content $logFile -Value $logMessage
        Write-Host "Attempt to add $($user.displayName) to ${groupName} was: ${result}"
    }
    
    $allUsersAdded = ($userList | Where-Object { !$_.groupSuccess }).count -eq 0
    if ($allUsersAdded) {
        Write-Host "All users in generated set have been added to ${groupName}"
    } else {
        Write-Host "Some users have not yet been added to ${groupName}; Retrying"
    }
} until ($allUsersAdded)

# Pause before Cleanup
$option = Read-Host -Prompt "Enter 'keep' to skip the automatic cleanup of users"
if ($option -eq 'keep') {
    exit 0
}

Write-Host "Perform cleanup of users and groups"
Write-Host "Removing Group ${groupName}"
Remove-AzureADGroup -ObjectId $azGroup.ObjectId

foreach ($user in $userList) {
    Write-Host "Removing user $($user.displayName)"
    Remove-AzureADUser -ObjectId $user.azUser.ObjectId
}
