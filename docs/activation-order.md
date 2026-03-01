# Activation Order (Formal Process)

This document defines the required activation order after completing Baller Installer.

Do not skip steps. Each stage builds on the previous one.

---

# Stage 0 – Baseline (Post-Baller)

Preconditions:
- VPX launches
- PinUP Popper launches
- A simple test table loads

PASS Criteria:
- No crashes launching VPX
- Table loads successfully

---

# Stage 1 – Windows Hardening

Actions:
- Set power plan to High Performance
- Disable USB selective suspend
- Disable Fast Startup
- Disable sleep/hibernate
- Confirm monitor layout (playfield primary)

PASS:
- No USB disconnects
- Monitors remain stable after reboot

---

# Stage 2 – PinOne Device Validation

Actions:
- Confirm device visible in Device Manager
- Verify buttons register
- Verify plunger axis visible and smooth

PASS:
- Device consistent across reboot
- No ghost inputs
- Plunger axis stable at rest

---

# Stage 3 – VPX Input Mapping

Actions:
- Map flippers, start, exit, launch
- Bind plunger axis
- Calibrate plunger min/max

PASS:
- Flippers respond reliably
- Plunger strength proportional to pull
- Exit works 100%

---

# Stage 4 – DOF Bring-Up

Actions:
- Install/configure DOF
- Fire Output01–Output10 sequentially
- Confirm device matches mapping standard

PASS:
- All outputs correct
- No stuck solenoids
- Shaker only runs when triggered

---

# Stage 5 – LED Validation

Actions:
- Run test animation
- Confirm brightness stable
- Confirm no flicker

PASS:
- LEDs respond correctly
- No random activation

---

# Stage 6 – SSF 7.1 Calibration

Actions:
- Confirm Windows 7.1 configuration
- Run speaker test tones
- Validate directional audio

PASS:
- Ball rolling localized correctly
- Flippers in front corners
- No swapped channels

---

# Stage 7 – Health Report

Actions:
- Generate activation report
- Record PASS/FAIL per stage

PASS:
- Report generated successfully
- Failures include actionable guidance