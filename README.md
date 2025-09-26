# AmpBridge

A server application with UI for controlling audio systems that use serial communication. Written and designed to control ELAN amplifiers, but should work in theory with any serial-based audio system. The app also sends MQTT messages to Home Assistant and can be controlled via the [Home Assistant integration.]()

> **Quick Start**: TLDR? Jump to the [Docker installation](#quick-start-with-docker-recommended) section.

This system works as a serial sniffer and relay - which listens for serial commands from the controller and forwards them to the amplifier. Once the system learns what commands get sent for each control, we can send those commands on our own.

The nice thing is that the relay is bidirectional, so when the amp response comes back, we send it to the controller - making the controller aware of the amplifier's state. This allows you to continue using the ELAN/NICE app or other viewets you may have.

## Support the Project

AmpBridge is free and open source. If you find it useful, consider supporting development:

- **GitHub Sponsors**: [Sponsor MJ Kochuk](https://github.com/sponsors/MJCyto)
- **One-time donations**: Use the GitHub Sponsors page to make a one-time contribution

Please don't feel obligated to donate - but it's always appreciated 🩵

## Heads Up

### Audio hardware considerations
Given that I tested this application with my particular ELAN equipment, your mileage may vary. My equpment consists of:

gSC10 Controller -> SC1 serial to Via!Net adapter -> s1616A Amplifier

If you have an s1616A or any amp that only has a Via!Net connection, you will at least need an SC1. This app ships with commands I've found for my device, but I cannot confirm that they work for other amps, including other s1616A amps (given that configuration will differ from amp to amp).

To have the best chance of success, I recommend using a controller above the amp - one that uses serial. This app was only tested with RS232.

### Equipment
You'll need a few things to get started:
- RJ45 Crimper
- RJ45 plugs
- Ethernet cable (old/cheap should be fine)
- USB-to-serial adapters, one for the controller and one for the amp
  - You can take a chance with just one if using an s1616A, but again the commands may be incompatible with yours.
- DB9 to RJ45 adapters, one per serial adapter

### Volume Controls

Volume controls are handled programmatically - no manual command learning needed.

## Features
- **Cable Wiring Helper**: UI generates wiring diagrams for ELAN's non-standard pinouts
- **Command Learning**: Captures commands from existing controllers
- **Real-time Control**: Web interface with live updates
- **Home Assistant Integration**: MQTT bridge for smart home automation


## Supported Devices

Tested with: gSC10 Controller → SC1 adapter → s1616A Amplifier (RS232)

Should work with any ELAN system using serial communication.

## Architecture

AmpBridge is built on modern web technologies with a focus on performance and reliability. The system acts as a bidirectional serial relay that learns commands from existing controllers and enables modern control interfaces.

### Core Technology Stack

- **Elixir/OTP**: Robust, fault-tolerant backend with process supervision
- **Phoenix LiveView**: Real-time web interface with server-side rendering
- **Ecto/SQLite**: Lightweight database for configuration and learned commands
- **Tortoise MQTT**: Home Assistant integration and smart home connectivity
- **Circuits UART**: Hardware serial communication for RS232/RS485

### System Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   ELAN/NICE     │    │    AmpBridge     │    │  Serial to      │
│   Controller    │◄──►│   (Serial Relay) │◄──►│  Via!Net Adapter│
│                 │    │                  │    │  (SC1)          │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                         │
                                                         ▼
                                               ┌─────────────────┐
                                               │   Amplifier     │
                                               │   (s1616A)      │
                                               └─────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Web Interface   │
                    │  (LiveView UI)   │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  Home Assistant  │
                    │  (MQTT Bridge)   │
                    └──────────────────┘
```

### Key Components

#### 1. **Serial Communication Layer**
- **SerialManager**: Manages multiple USB-to-serial adapters
- **SerialRelay**: Bidirectional data forwarding between controller and amplifier
- **SerialDecoder**: ELAN protocol parsing and command interpretation
- **USBDeviceScanner**: Automatic detection and assignment of serial devices

#### 2. **Command Learning System**
- **CommandLearner**: Orchestrates the learning process for new commands
- **CommandLearningSession**: Captures and stores command sequences
- **ResponsePatternMatcher**: Validates command responses
- **HexCommandManager**: Manages learned command storage and retrieval

#### 3. **Hardware Management**
- **HardwareManager**: Supervisor for all hardware controllers
- **HardwareController**: Individual amplifier control and command execution
- **ZoneManager**: Volume control and zone state tracking

#### 4. **Web Interface**
- **LiveView Pages**: Real-time UI for system configuration and control
  - Home dashboard with system status
  - Initialization wizard (USB assignment, zone setup, command learning)
  - Serial analysis and debugging tools
  - Ethernet wiring diagram generator
- **Components**: Reusable UI elements for device configuration
- **Real-time Updates**: Phoenix PubSub for live synchronization

#### 5. **Data Layer**
- **SQLite Database**: Configuration storage and command persistence
- **AudioDevice Schema**: Device configuration, zones, sources, and states
- **LearnedCommands**: Captured command sequences and response patterns
- **SerialCommands**: Pre-configured commands for common operations

#### 6. **Smart Home Integration**
- **MQTTClient**: Publishes zone states and accepts control commands
- **Home Assistant Integration**: Custom component for seamless automation
- **State Synchronization**: Real-time updates between web UI and smart home

### Process Supervision Tree

```
AmpBridge.Application
├── AmpBridgeWeb.Telemetry
├── AmpBridge.Repo
├── Phoenix.PubSub
├── Registry (Hardware Controllers)
├── Registry (Command Learning Sessions)
├── AmpBridge.USBDeviceScanner
├── AmpBridge.HardwareManager
│   └── AmpBridge.HardwareController
├── AmpBridge.SerialDecoder
├── AmpBridge.SerialManager
├── AmpBridge.SerialRelay
├── AmpBridge.ZoneManager
├── AmpBridge.MQTTClient
└── AmpBridgeWeb.Endpoint
```

### Real-Time Features

- **Live Volume Control**: Multi-user synchronized volume adjustments
- **Command Learning**: Interactive capture of new control commands
- **Serial Monitoring**: Real-time display of serial communication
- **State Broadcasting**: Automatic updates across all connected clients
- **Error Recovery**: Automatic retry and fallback mechanisms

### Data Flow

1. **Initialization**: USB device detection → Serial connection → Zone configuration
2. **Command Learning**: User interaction → Serial capture → Pattern analysis → Storage
3. **Normal Operation**: UI control → Command lookup → Serial transmission → State update
4. **Smart Home**: MQTT message → Command execution → State synchronization

This architecture enables AmpBridge to serve as a modern bridge between legacy audio systems and contemporary smart home automation, while maintaining compatibility with existing control interfaces.

## Getting Started

### Prerequisites

- Docker and Docker Compose
- Communication hardware appropriate for your audio system (serial, IR, network, etc.)
- MQTT broker (optional, for smart home integration)

### Quick Start with Docker (Recommended)

The easiest way to get AmpBridge running is with Docker:

1. **Pull the latest image:**
   ```bash
   docker pull cytotoxicdingus/ampbridge:latest
   ```

2. **Run the container with USB device access:**
   ```bash
   docker run -p 4000:4000 -p 1885:1885 --privileged \
     -v /dev/bus/usb:/dev/bus/usb \
     -v ampbridge-data:/app/data \
     cytotoxicdingus/ampbridge:latest
   ```

3. **Access the web interface:**
   Open [http://localhost:4000](http://localhost:4000) in your browser

**Important Notes:**
- The `--privileged` flag and USB volume mount are required for serial device access
- The data volume mount (`-v ampbridge-data:/app/data`) ensures your configuration persists between restarts
- Port 4000 is for the web interface, port 1885 is for the built-in MQTT broker

### Docker Compose (Alternative)

For easier management, you can use Docker Compose:

```yaml
version: '3.8'
services:
  ampbridge:
    image: cytotoxicdingus/ampbridge:latest
    ports:
      - "4000:4000"
      - "1885:1885"
    privileged: true
    volumes:
      - /dev/bus/usb:/dev/bus/usb
      - ampbridge-data:/app/data
    restart: unless-stopped

volumes:
  ampbridge-data:
```

Save this as `docker-compose.yml` and run:
```bash
docker-compose up -d
```

### Manual Installation (Development)

For development or if you prefer to build from source:

**Prerequisites:**
- Elixir 1.14+ and Erlang 24+
- Node.js 18+ (for asset compilation)

**Steps:**
1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/ampbridge.git
   cd ampbridge
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Configure your environment:
   ```bash
   cp config/dev.exs.example config/dev.exs
   # Edit config/dev.exs with your device settings
   ```

4. Start the development server:
   ```bash
   mix phx.server
   ```

5. Open [http://localhost:4000](http://localhost:4000) in your browser

### Configuration

The web interface guides you through setup:
1. USB device assignment
2. Zone and source configuration  
3. Command learning from your existing controller

## Usage

Once running, the web interface provides:
- Zone volume and mute controls
- Source selection and routing
- Real-time status updates
- Home Assistant integration via MQTT

## Real-Time Features

- **Multi-user sync**: Volume changes appear instantly across all connected devices
- **Live updates**: All settings and status changes broadcast in real-time
- **No conflicts**: Multiple users can control the system simultaneously

## Hardware Integration

AmpBridge automatically translates web controls into serial commands for your amplifier. No manual configuration needed - it learns commands from your existing controller.

## Development

### Project Structure

```
ampbridge/
├── config/                # Configuration files
├── lib/                   # Core application logic
│   ├── amp_bridge/        # Core business logic and audio device management
│   └── amp_bridge_web/    # Web interface and LiveView components
│       ├── components/     # Reusable UI components
│       ├── controllers/    # HTTP controllers
│       ├── live/          # LiveView pages and real-time functionality
│       └── layouts/       # Page layouts and templates
├── priv/                  # Database migrations and seeds
└── test/                  # Test suite
```

### Key Components

- **Serial Communication**: USB-to-serial adapters for hardware control
- **Command Learning**: Captures and replays controller commands
- **Web Interface**: Real-time control panel
- **MQTT Bridge**: Home Assistant integration

### Testing

Run the test suite:

```bash
mix test
```

Run specific test categories:

```bash
mix test test/amp_bridge_web/live/
mix test test/amp_bridge/
```

## Contributing

We welcome contributions! Please reach out if you wish to begin.

## License

AmpBridge © 2025 by MJ Kochuk is licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).

This means you are free to:
- **Share** — copy and redistribute the material in any medium or format
- **Adapt** — remix, transform, and build upon the material

Under these terms:
- **Attribution** — You must give appropriate credit and indicate if changes were made
- **NonCommercial** — You may not use the material for commercial purposes  
- **ShareAlike** — If you remix or build upon the material, you must distribute under the same license

See the [LICENSE](LICENSE) file for the full license text.

## Support

For support and questions, please open a GitHub issue:

- **Issues**: [GitHub Issues](https://github.com/your-org/ampbridge/issues)

When reporting issues, please include:
- Your hardware setup (controller, adapter, amplifier models)
- Steps to reproduce the problem
- Any error messages or logs
- Screenshots if applicable

## Roadmap

I'm actively working on improvements to AmpBridge. One of the first features I'm adding is a log generation tool that will help users create detailed logs for troubleshooting without compromising privacy - the app will generate the logs locally for you to review and send privately if needed.

Other areas I'm exploring:
- Enhanced device discovery and auto-configuration
- Better error handling and recovery
- More amplifier models and protocols (defaults for setup)
- Improved command learning workflow

---

**AmpBridge** - Bridging the gap between complex audio systems and modern control interfaces.
