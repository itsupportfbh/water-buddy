Water Buddy — Windows desktop water reminders

A bottle-carrying animated companion with English reminders, drink logging,
happy/sad reactions, 5/10/15-minute snooze and a local dashboard.

Windows 10/11. Reminders run hourly from 7 AM through 4 PM, local time,
while the user is signed in and the PC is awake. Browser access is not required.
No cloud account, paid subscription or network service is needed by the app.
The reminder plan is a habit aid, not a medical prescription.

INSTALL
The existing unsigned release is available at:
https://water-buddy-reminder.vercel.app/#desktop-install
The setup installs to the current user's LocalAppData\WaterBuddy folder,
creates a sign-in startup shortcut and opens the companion after setup.
Exit the app from its tray menu before updating. User data is retained.
Uninstall via Windows Settings > Apps. Saved drink history is retained.
Unsigned releases may trigger browser/Windows warnings; do not disable protections.

BUILD FROM SOURCE
Install Inno Setup from https://jrsoftware.org/isinfo.php and review its license.
This project was tested with Inno Setup 6.7.4, Windows PowerShell 5.1 and .NET
Framework WPF/Windows Forms included with Windows. Inno Setup is a separate
build dependency; its binaries are not vendored or relicensed in this repository.

Run in PowerShell from the project directory:
  .\build.ps1 -Compiler 'C:\Path\To\Inno Setup 6\ISCC.exe'
Output: artifacts\Water-Buddy-Setup.exe (unsigned)
UI smoke test (opens temporary windows):
  powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\app\WaterReminder.ps1 -SmokeTest

CODE SIGNING POLICY
No SignPath sponsorship or signing approval has been granted at this time.
See docs\code-signing-policy.txt for the proposed process and remaining steps.
See docs\privacy.txt for local data behavior. Original project code and included
mascot assets are offered under the MIT license; see LICENSE.

PUBLIC SOURCE: https://github.com/itsupportfbh/water-buddy
Builds: https://github.com/itsupportfbh/water-buddy/actions
Maintainer / reviewer / proposed signing approver: https://github.com/itsupportfbh
GitHub Actions builds unsigned artifacts from published commits. Signing is not yet configured or approved.
