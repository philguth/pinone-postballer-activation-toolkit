# Windows 11 Hardening for Pinball Cabinet

## Goal
Prepare a Windows 11 machine to behave like a cabinet appliance:
- Dedicated runtime user
- Auto-login
- No sleep/USB dropouts
- Stable device enumeration (PinOne, audio, plunger, etc.)
- Predictable boot to front-end

## Step 0 — Create a Dedicated Cabinet Account (Local)
1. Settings → Accounts → Other users
2. Add account
3. Choose "I don’t have this person’s sign-in information"
4. Choose "Add a user without a Microsoft account"
5. Create:
   - Username: `Pinball`
   - Password: optional (can be blank)
6. Set the account type to Administrator:
   - Settings → Accounts → Other users → `Pinball` → Change account type → Administrator

## Step 1 — Enable Auto-Login for the Cabinet Account
### Option A (Preferred): netplwiz
1. Win+R → `netplwiz`
2. Uncheck: "Users must enter a username and password to use this computer"
3. Apply → enter the `Pinball` credentials (if you set a password)
4. Reboot and confirm it signs in automatically

### Option B: Registry (Winlogon AutoAdminLogon)
If netplwiz is not available or checkbox is missing:
- Set these registry values under:
  `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`

Keys:
- `AutoAdminLogon` = `1`
- `DefaultUserName` = `Pinball`
- `DefaultDomainName` = `.` (local machine) or machine name
- `DefaultPassword` = (only required if a password exists)

**Security note:** Storing `DefaultPassword` in registry is not ideal. For a dedicated cabinet PC, this is often acceptable.

## Step 2 — Disable Sleep / Hibernation (AC Power)
Recommended settings:
- Turn off display: Never (or long duration)
- Put device to sleep: Never

Also recommended:
- Disable hibernation:
  - Admin terminal: `powercfg /hibernate off`

## Step 3 — Disable USB Selective Suspend
This reduces USB device dropouts and reconnects.

- Control Panel → Power Options → Change plan settings → Advanced
- USB settings → USB selective suspend setting → Disabled

## Step 4 — Disable Fast Startup
Fast Startup can preserve a weird pre-boot hardware state.

- Control Panel → Power Options → Choose what the power buttons do
- Change settings that are currently unavailable
- Uncheck "Turn on fast startup"

## Step 5 — Set a “Cabinet-Friendly” Power Plan
- Prefer High performance (if available)
- Otherwise use Balanced but disable sleep/USB suspend

## Step 6 — Auto-Launch Front-End on Login
Choose one:
- Startup folder shortcut (simple)
- Scheduled Task (reliable; runs with delays; can run elevated)
- Registry Run key (common; less flexible)

**PASS target:**
Boot → auto-login as `Pinball` → front-end launches.

## Step 7 — Validate
Run:
- `/scripts/validate-windows.ps1`

Fix anything that reports FAIL before you proceed to device activation and PinOne testing.