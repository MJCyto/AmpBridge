# ELAN Volume Control Protocol - Complete Reference
## Universal Protocol for All Zones

### 📊 **Protocol Overview**
- **System**: ELAN GSC10 Adapter via RS232
- **Control Method**: Button-based incremental control
- **Volume Range**: 0% to 100%
- **Zones Supported**: Zone 1, Zone 2 (Zone 3+ pending)

### 🔍 **Command Structure**
```
Command: a4 02 01 fd a4 08 20 [ZONE] [VOLUME_LEVEL] [ZONE]
Response: 64 4b 4b 01 80 02 [CHECKSUM]
```

### 🎯 **Universal Control Scheme**

**ELAN Volume Control is Button-Based, Not Percentage-Based:**

1. **Volume UP Button**: Commands 0x37 to 0x3c (175 levels)
   - Incremental up button presses
   - Fine control (175 steps)
   - Response shows current volume level
   - **IDENTICAL across all zones**

2. **Volume DOWN Button**: Zone-specific command ranges
   - Incremental down button presses  
   - Zone 1: 0x3f-0xa2 (101 levels)
   - Zone 2: 0x61-0xc4 (101 levels) - **+0x22 offset from Zone 1**
   - Response shows remaining volume capacity

### 📈 **Zone 1 Volume UP Mapping (Universal)**

| Volume % | Command | Response Level | Checksum | Notes |
|----------|---------|----------------|----------|-------|
| 0% | 0x37 | 0x38 | 0xda | Minimum volume |
| 25% | 0x53 | 0x1a | 0xdc | Quarter volume |
| 50% | 0x72 | 0x09 | 0xce | Half volume |
| 75% | 0x8b | 0x22 | 0x9c | Three quarters |
| 100% | 0x3c | 0x64 | 0xa9 | Maximum volume |

### 📉 **Zone 1 Volume DOWN Mapping**

| Volume % | Command | Response Level | Checksum | Notes |
|----------|---------|----------------|----------|-------|
| 95% | 0x3f | 0x63 | 0xa7 | Down from 100% |
| 75% | 0x63 | 0x3f | 0xa7 | Down button press |
| 50% | 0x90 | 0x12 | 0xa7 | Down button press |
| 25% | 0xa2 | 0x01 | 0xa7 | Down button press |
| 5% | 0xa1 | 0x01 | 0xa7 | Near minimum |

### 📉 **Zone 2 Volume DOWN Mapping**

| Volume % | Command | Response Level | Checksum | Notes |
|----------|---------|----------------|----------|-------|
| 95% | 0x61 | 0x63 | 0x83 | Down from 100% |
| 75% | 0x85 | 0x1f | 0x83 | Down button press |
| 50% | 0xa9 | 0x0b | 0x83 | Down button press |
| 25% | 0xcd | 0xe7 | 0x83 | Down button press |
| 5% | 0xc3 | 0x01 | 0x83 | Near minimum |

### 🔧 **Universal Command Generator**

#### **Volume UP Commands (All Zones)**
| Volume % | Hex Command | Minicom Command |
|----------|-------------|-----------------|
| 0% | `a4 02 01 fd a4 08 20 02 37 01` | `a4 02 01 fd a4 08 20 02 37 01` |
| 25% | `a4 02 01 fd a4 08 20 02 53 01` | `a4 02 01 fd a4 08 20 02 53 01` |
| 50% | `a4 02 01 fd a4 08 20 02 72 01` | `a4 02 01 fd a4 08 20 02 72 01` |
| 75% | `a4 02 01 fd a4 08 20 02 8b 01` | `a4 02 01 fd a4 08 20 02 8b 01` |
| 100% | `a4 02 01 fd a4 08 20 02 3c 01` | `a4 02 01 fd a4 08 20 02 3c 01` |

#### **Zone 1 Volume DOWN Commands**
| Volume % | Hex Command | Minicom Command |
|----------|-------------|-----------------|
| 95% | `a4 02 01 fd a4 08 20 02 3f 01` | `a4 02 01 fd a4 08 20 02 3f 01` |
| 75% | `a4 02 01 fd a4 08 20 02 63 01` | `a4 02 01 fd a4 08 20 02 63 01` |
| 50% | `a4 02 01 fd a4 08 20 02 90 01` | `a4 02 01 fd a4 08 20 02 90 01` |
| 25% | `a4 02 01 fd a4 08 20 02 a2 01` | `a4 02 01 fd a4 08 20 02 a2 01` |
| 5% | `a4 02 01 fd a4 08 20 02 a1 01` | `a4 02 01 fd a4 08 20 02 a1 01` |

#### **Zone 2 Volume DOWN Commands**
| Volume % | Hex Command | Minicom Command |
|----------|-------------|-----------------|
| 95% | `a4 02 01 fd a4 08 20 03 61 02` | `a4 02 01 fd a4 08 20 03 61 02` |
| 75% | `a4 02 01 fd a4 08 20 03 85 02` | `a4 02 01 fd a4 08 20 03 85 02` |
| 50% | `a4 02 01 fd a4 08 20 03 a9 02` | `a4 02 01 fd a4 08 20 03 a9 02` |
| 25% | `a4 02 01 fd a4 08 20 03 cd 02` | `a4 02 01 fd a4 08 20 03 cd 02` |
| 5% | `a4 02 01 fd a4 08 20 03 c3 02` | `a4 02 01 fd a4 08 20 03 c3 02` |

### 🔍 **Zone Comparison**

| Feature | Zone 1 | Zone 2 | Status |
|---------|--------|--------|--------|
| Volume UP Header | `20 02` | `20 02` | ✅ Identical |
| Volume UP Range | 0x37-0x3c | 0x37-0x3c | ✅ Identical |
| Volume UP Zone | 01 | 01 | ✅ Identical |
| Volume DOWN Header | `20 02` | `20 03` | ❌ Different |
| Volume DOWN Range | 0x3f-0xa2 | 0x61-0xc4 | ❌ Different (0x22 offset) |
| Volume DOWN Zone | 01 | 02 | ❌ Different |

### 🎯 **Key Discoveries**

1. **Volume UP is Universal**: All zones use identical commands (0x37-0x3c, 175 levels)
2. **Volume DOWN is Zone-Specific**: 
   - Zone 1: 0x3f-0xa2 (101 levels) with header `20 02`
   - Zone 2: 0x61-0xc4 (101 levels) with header `20 03` - **+0x22 offset**
3. **Button-Based Control**: No direct percentage setting - only incremental button presses
4. **Digital End Stop Challenge**: Must track current volume level in software

### 💡 **Universal Controller Implementation**

```python
def get_volume_up_command(volume_level):
    """Universal volume UP command for all zones"""
    base_command = 0x37 + volume_level
    return f"a4 02 01 fd a4 08 20 02 {base_command:02x} 01"

def get_volume_down_command(zone, volume_level):
    """Zone-specific volume DOWN command"""
    if zone == 1:
        base_command = 0x3f + volume_level
        return f"a4 02 01 fd a4 08 20 02 {base_command:02x} 01"
    elif zone == 2:
        base_command = 0x61 + volume_level  # 0x3f + 0x22 + volume_level
        return f"a4 02 01 fd a4 08 20 03 {base_command:02x} 02"
    else:
        raise ValueError(f"Unsupported zone: {zone}")

def set_volume_to_percentage(zone, target_percentage, current_volume=0):
    """Simulate button presses to reach target volume"""
    if target_percentage > current_volume:
        # Use volume UP commands
        steps = target_percentage - current_volume
        for _ in range(steps):
            send_command(get_volume_up_command(current_volume + 1))
    elif target_percentage < current_volume:
        # Use volume DOWN commands
        steps = current_volume - target_percentage
        for _ in range(steps):
            send_command(get_volume_down_command(zone, current_volume - 1))
```

### 📊 **Data Collection Status**

- ✅ Zone 1: Volume UP (0% to 100%) - 175 levels
- ✅ Zone 1: Volume DOWN (100% to 0%) - 101 levels
- ✅ Zone 2: Volume UP (0% to 100%) - 175 levels  
- ✅ Zone 2: Volume DOWN (100% to 0%) - 101 levels
- ❌ Zone 3+: Pending testing

### 🧪 **Testing Commands**

```bash
# Test Zone 1 volume 50%
echo "a4 02 01 fd a4 08 20 02 72 01" | minicom -D /dev/ttyUSB0

# Test Zone 2 volume 50%
echo "a4 02 01 fd a4 08 20 02 72 01" | minicom -D /dev/ttyUSB0

# Test Zone 1 volume down 50%
echo "a4 02 01 fd a4 08 20 02 90 01" | minicom -D /dev/ttyUSB0

# Test Zone 2 volume down 50%
echo "a4 02 01 fd a4 08 20 03 a9 02" | minicom -D /dev/ttyUSB0
```

### ⚠️ **Important Notes**

1. **Digital End Stop Required**: Without knowing current volume level, you cannot reliably reach a target volume by simulating button presses
2. **Zone Detection**: Must detect which zone you're controlling to use correct volume DOWN commands
3. **Response Monitoring**: Monitor responses to track actual volume level changes
4. **Error Handling**: Implement timeout and error detection for failed commands

### 🔧 **Hardware Requirements**

- ELAN GSC10 Adapter
- RS232 connection (USB-to-Serial adapter)
- Minicom or similar terminal emulator
- Python/Node.js for automation (optional)

### 📝 **Protocol Summary**

The ELAN volume control protocol uses button-based incremental control with:
- **Universal Volume UP**: Same commands across all zones
- **Zone-Specific Volume DOWN**: Different command ranges per zone
- **Response Monitoring**: Track volume level changes via responses
- **Button Simulation**: Use incremental commands to reach target volumes

This protocol enables building universal ELAN controllers that can work across different systems and zones.
