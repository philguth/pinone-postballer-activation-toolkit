# Hardware Mapping Standard (v0.1)

This document defines the canonical hardware mapping standard for:

- CSD PinOne Controller
- 10 Solenoids
- Shaker Motor
- LED Matrix
- Addressable LED Strips
- SSF 7.1 Audio

The goal is to eliminate ambiguity and create a known-good baseline for activation and validation.

---

# Design Principles

1. Logical device names must be consistent across all cabinets.
2. Output numbering must be deterministic.
3. Physical wiring labels should match documentation.
4. Scripts must be able to validate against this standard.

---

# Canonical Naming Convention

## Logical Name Format

- `Solenoid.LeftFlipper`
- `Solenoid.RightFlipper`
- `Motor.Shaker`
- `Lighting.LedMatrix`
- `Axis.Plunger`
- `Input.Start`

## Physical Label Recommendation

Each physical device should have a sticker label:

- COIL01–COIL10
- LEDSTRIP01
- MATRIX01
- PINONE01
- AMP01

---

# PinOne Output Mapping Standard (10 Outputs)

| Output | Logical Device | Physical Label | Notes |
|--------|----------------|---------------|-------|
| Output01 | Solenoid.LeftFlipper | COIL01 | Primary tactile device |
| Output02 | Solenoid.RightFlipper | COIL02 |  |
| Output03 | Solenoid.LeftSling | COIL03 |  |
| Output04 | Solenoid.RightSling | COIL04 |  |
| Output05 | Solenoid.Bumper1 | COIL05 | Top-left bumper |
| Output06 | Solenoid.Bumper2 | COIL06 | Top-middle bumper |
| Output07 | Solenoid.Bumper3 | COIL07 | Top-right bumper |
| Output08 | Solenoid.Knocker | COIL08 | Optional if installed |
| Output09 | Motor.Shaker | COIL09 | MOSFET/relay driven |
| Output10 | Solenoid.Gear | COIL10 | Spare / Ball release |

---

# Required Cabinet Inputs

Minimum supported inputs:

- Input.Start
- Input.Coin
- Input.Exit
- Input.Launch
- Input.LeftFlipper
- Input.RightFlipper
- Input.LeftMagnaSave
- Input.RightMagnaSave
- Axis.Plunger (analog)

Optional:

- Input.Service
- Input.VolumeUp
- Input.VolumeDown

---

# SSF 7.1 Audio Mapping Standard

| Windows Channel | Physical Location |
|-----------------|------------------|
| Front Left | Front-left exciter |
| Front Right | Front-right exciter |
| Center | Backbox center |
| LFE/Sub | Subwoofer |
| Surround Left | Left side exciter |
| Surround Right | Right side exciter |
| Rear Left | Rear-left exciter |
| Rear Right | Rear-right exciter |

Windows must be configured as 7.1.

---

# LED Configuration

## LED Matrix
- Enabled: true/false
- Device connection: USB or COM

## Addressable LED Strips
- Enabled: true/false
- Pixel count (if known)
- Controlled via PinOne or external controller