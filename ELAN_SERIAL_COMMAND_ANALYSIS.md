# ELAN Audio Control Protocol

## Overview

This document describes the ELAN audio control protocol discovered through reverse engineering the manufacturer's app communication patterns. It covers commands for volume and bass, and can be extended to other audio parameters in the future.

---

## Command Structure

All audio control commands follow this general structure:

```

A4 05 06 FF 0B [command_type] [zone] [value_byte1] [value_byte2] [checksum]

```

### Command Breakdown

| Byte | Meaning                       | Notes                                                                                   |
| ---- | ----------------------------- | --------------------------------------------------------------------------------------- |
| 1-2  | `A4 05`                       | Command start marker                                                                    |
| 3-5  | `06 FF 0B`                    | Command identifier (category/family)                                                    |
| 6    | `[command_type]`              | **Command type** — selects what you’re controlling, e.g., `10` = volume, `11` = bass   |
| 7    | `[zone]`                      | Zone selector (`01` = zone 1, `02` = zone 2, etc.)                                      |
| 8-9  | `[value_byte1] [value_byte2]` | 16-bit encoded value, depends on command type (volume, bass, etc.)                      |
| 10   | `[checksum]`                  | XOR of all previous bytes                                                               |

---

## Command Types

| Command Type | Description                                        |
| ------------ | -------------------------------------------------- |
| `10`         | Volume                                             |
| `11`         | Bass                                               |
| TBD          | Treble / other audio parameters (to be discovered) |

---

## Value Bytes

### Volume Encoding

* The two volume bytes encode a value from 0–100%.
* Observed pattern: the two bytes **sum to 217 (0xD9)** in decimal.
* This allows approximate 0–100% volume control.

| Volume % | value_byte1 | value_byte2 |
| -------- | ----------- | ----------- |
| 0%       | 0x00        | 0xD9        |
| 25%      | 0x19        | 0xC0        |
| 50%      | 0x32        | 0xA7        |
| 100%     | 0x64        | 0x75        |

> Note: The first byte roughly represents the percentage, the second byte completes the sum to 217.

---

### Bass Encoding

* Command type for bass is `11`.
* Observed 16-bit values for extreme positions:

| Zone | Bass Level | value_byte1 | value_byte2 |
| ---- | ---------- | ----------- | ----------- |
| 1    | Min        | F4          | E5          |
| 1    | Max        | 0C          | CD          |
| 2    | Min        | F4          | E4          |
| 2    | Max        | 0C          | CC          |

> Note: The first byte appears to encode the main magnitude, the second byte may be zone-specific or adjusted. The exact 0–100 mapping for bass is not fully determined yet.

---

## Checksum

* The last byte in each command is a checksum.
* Calculated as **XOR of all previous bytes** in the command.

---

## Observations

* **Command Structure** is consistent across volume and bass: start marker → category → type → zone → value → checksum.
* **Command Type** differentiates the parameter being controlled (`10` = volume, `11` = bass).
* **Zone Selector** allows control of multiple zones independently (`01`, `02`, etc.).
* **Value Bytes** encode the parameter level; volume has a known 0–100 mapping, bass mapping partially observed.
* **Checksum** ensures data integrity.

---

## Limitations & Notes

* **Exact mappings** for bass (and other parameters like treble) are not fully reverse-engineered.
* **Timing** of commands may be important for proper reception.
* **Each zone** requires separate commands for independent control.
* Other audio parameters may exist; the same byte positions would likely apply.