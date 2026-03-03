# Cabinet OS Baseline Standard (Windows 11)

## Purpose
Define the minimum Windows 11 configuration required for a reliable virtual pinball cabinet runtime environment.

This baseline is designed for:
- Dedicated cabinet account ("Pinball")
- No keyboard/mouse required after initial setup
- Predictable boot → front-end launch
- Stable USB device behavior (PinOne, audio, plunger, etc.)
- Reduced power-saving interruptions

## Scope
Applies to:
- Windows 11 Home or Pro
- Single-PC cabinet builds or external-PC-to-cabinet builds
- PinOne + Solenoids + SSF 7.1 + LED matrix / addressable LED setups

## Roles
- **Admin / Build Account**: Used for installations, driver updates, tuning, and troubleshooting.
- **Cabinet / Runtime Account**: Used for daily cabinet operation.

## Baseline Requirements

### R1. Dedicated Local Cabinet Account
- A local Windows account MUST exist for cabinet runtime (recommended name: `Pinball`)
- The cabinet account SHOULD be a local account (not a Microsoft account)
- The cabinet account SHOULD be an Administrator (driver/hardware access is often required)

**PASS if:** A local `Pinball` user exists and can sign in successfully.

### R2. Automatic Sign-In (No Login Prompt)
- System SHOULD automatically sign into the cabinet account on boot
- No interactive password entry should be required at boot

**PASS if:** Reboot leads directly to desktop/session under `Pinball` without credential entry.

### R3. Power and Sleep Behavior
- Sleep MUST be disabled for AC power (cabinet operation)
- Display sleep SHOULD be disabled or set long enough to not interrupt play
- Hibernation SHOULD be disabled (optional but recommended)

**PASS if:** No sleep/hibernate occurs during normal cabinet operation.

### R4. USB Power Management
- USB selective suspend SHOULD be disabled (prevents device dropouts)
- System SHOULD avoid powering down USB hubs/devices

**PASS if:** Devices remain enumerated and responsive after long idle periods.

### R5. Fast Startup
- Fast Startup SHOULD be disabled (common source of weird device/driver states)

**PASS if:** Fast Startup is disabled and cold boot behaves consistently.

### R6. Windows Update / Restart Behavior (Operational)
- Active hours SHOULD be configured
- Reboot prompts should not interrupt play sessions

**PASS if:** Cabinet can remain stable through play sessions without surprise reboots.

### R7. Front-End Launch (Cabinet Experience)
- Front-end SHOULD auto-launch on login (PinUP Popper or chosen front-end)
- Desktop exposure SHOULD be minimized (optional but recommended)

**PASS if:** After boot/login, front-end becomes the primary UI without manual action.

## Validation
- Run: `/scripts/validate-windows.ps1`
- Document results in the project logs (optional)

## Notes / Tradeoffs
- Auto-logon reduces physical friction but has security implications.
- Admin cabinet accounts are convenient but less secure; acceptable for dedicated offline cabinets.