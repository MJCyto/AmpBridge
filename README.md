# AmpBridge

A server application with UI for controlling audio systems that use serial communication. Written and designed to control ELAN amplifiers, but should work in theory with any serial-based audio system. The app also sends MQTT messages to Home Assistant and can be controlled via the [Home Assistant integration.]()

This system works as a serial sniffer and relay - which listens for serial commands from the controller and forwards them to the amplifier. Once the system learns what commands get sent for each control, we can send those commands on our own.

The nice thing is that the relay is bidirectional, so when the amp response comes back, we send it to the controller - making the controller aware of the amplifier's state. This allows you to continue using the ELAN/NICE app or other viewets you may have.

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

From what I was able to tell, the volume controls are fairly generic. I've gone through the effort to have the app generate the serial commands for volume changes programmatically, but I plan on adding "command learning" capabilities in the future for volume control, much like the other commands. This will be a pain in the butt for anyone going this route since the ELAN's UI kinda blows!

## Features
- Since ELAN loves to make up their own rules, a lot of their serial connections have pinouts that are abnormal. I've made a UI that allows you to input what each pin is for (ELANs manuals can have this info, and your DB9 to RJ45 adapters should be 1:1, mor eon this later). The UI will give you a diagram to help you crimp your cables.
- 

### Core Functionality
- **Zone Management**: Configure and manage multiple audio zones with custom names, default settings, and grouping capabilities
- **Media Source Control**: Assign and manage multiple media inputs with flexible routing to zones
- **Command Configuration**: Customizable command mapping for any audio device (serial, IR, network, or custom protocols)
- **Real-time State Management**: Live updates and status monitoring for all zones and sources
- **Smart Home Integration**: MQTT-based integration for Home Assistant automations and scripts

### Technical Capabilities
- **Caching System**: Persistent configuration storage with IndexedDB and SWR for optimal performance
- **Component Architecture**: Modular, reusable components for maintainable development
- **Advanced Table Views**: Sophisticated data management with grouping, filtering, and bulk operations
- **Drag & Drop Interface**: Intuitive zone and source assignment workflows
- **Nested Data Management**: Complex configuration hierarchies with efficient state handling

## Supported Devices

AmpBridge is designed to work with any audio matrix system or amplifier through flexible protocol support:

- **Audio Matrices**: Multi-zone audio distribution systems
- **Amplifiers**: Power amplifiers with zone control capabilities
- **Protocols**: Serial (RS-232/RS-485), IR, network (TCP/UDP), custom protocols
- **Manufacturers**: ELAN, Russound, NuVo, Sonos, and many others
- **Custom Integration**: Extensible architecture for proprietary or custom audio systems

## Architecture

AmpBridge is built on modern web technologies with a focus on performance and reliability:

- **Backend**: Elixir with Phoenix LiveView for real-time updates
- **Frontend**: Modern web components with responsive design
- **Communication**: Serial (RS-232/RS-485), IR, network protocols, and custom communication methods
- **Integration**: MQTT broker for smart home connectivity
- **Storage**: Local configuration persistence with cloud sync capabilities

## Getting Started

### Prerequisites

- Elixir 1.14+ and Erlang 24+
- Node.js 18+ (optional, for asset compilation)
- Communication hardware appropriate for your audio system (serial, IR, network, etc.)
- MQTT broker (optional, for smart home integration)

### Installation

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

### Docker Installation

For easy deployment, AmpBridge can be run using Docker:

1. Build the Docker image:
   ```bash
   sudo docker build -t ampbridge:local .
   ```

2. Run the container with USB device access:
   ```bash
   sudo docker run -p 4000:4000 -p 1885:1885 --privileged -v /dev/bus/usb:/dev/bus/usb ampbridge:local
   ```

3. Access the web interface at [http://localhost:4000](http://localhost:4000)

**Note**: The `--privileged` flag and USB volume mount are required for serial device access. The application needs to communicate with USB-to-serial adapters connected to your audio hardware.

### Configuration

The application requires configuration of your specific audio system:

1. **Device Setup**: Configure communication protocols and connections for your audio system
2. **Zone Configuration**: Define your audio zones and their properties
3. **Source Mapping**: Map media sources to available inputs
4. **Command Library**: Define the control commands for your specific devices and protocols
5. **MQTT Integration**: Configure broker settings for smart home connectivity

## Usage

### Zone Management

Create and configure audio zones with:
- Custom naming conventions
- Default volume levels
- Source assignments
- Grouping for logical organization
- Enable/disable controls

### Source Control

Manage media sources with:
- Input-to-output routing
- Multiple zone support per source
- Concurrent playback capabilities
- Volume and mute controls

### Smart Home Integration

Once configured, AmpBridge exposes:
- MQTT topics for each zone and source
- State information for automation triggers
- Control entities for Home Assistant
- Real-time status updates

## Real-Time Volume Control

AmpBridge now supports real-time volume control updates across multiple users. When one user adjusts a volume slider, the changes are immediately visible to all other users viewing the same devices.

### How It Works

1. **PubSub Broadcasting**: All volume changes are broadcasted through Phoenix PubSub to a `device_updates` topic
2. **LiveView Subscriptions**: Each LiveView subscribes to the topic to receive real-time updates
3. **Automatic Synchronization**: When a user changes a volume, all other users see the update instantly

### Supported Real-Time Updates

- **Our Master Volume**: The global master volume control
- **Device Master Volume**: Individual device master volume settings
- **Output Volume Controls**: Individual output channel volumes
- **Device Creation/Deletion**: New devices appear and deleted devices disappear in real-time
- **All Device Settings**: Any changes to device settings are synchronized

### Technical Implementation

The real-time functionality is implemented using:

- **Phoenix PubSub**: For broadcasting changes across all connected users
- **LiveView Subscriptions**: Each LiveView subscribes to the `device_updates` topic
- **Automatic Broadcasting**: All database changes automatically trigger PubSub broadcasts
- **Efficient Updates**: Only the changed device data is transmitted, minimizing bandwidth

### Usage

Simply open the AmpBridge application in multiple browser tabs or devices. When you adjust any volume control in one tab, you'll see the changes reflected immediately in all other tabs.

This enables collaborative audio system management where multiple users can work together in real-time without conflicts or synchronization issues.

## Hardware Management System

AmpBridge includes a sophisticated hardware management system that automatically translates volume and setting changes into serial commands for physical amplifiers.

### Architecture

The hardware management system consists of:

1. **HardwareManager** (Supervisor): Manages all hardware controllers as a singleton process
2. **HardwareController** (Worker): Controls a specific amplifier and subscribes to device updates
3. **Serial Communication**: Sends RS232 commands via USB serial adapters

### How It Works

1. **Automatic Subscription**: Each hardware controller automatically subscribes to device updates
2. **Command Generation**: Volume/setting changes are translated into appropriate serial commands
3. **Serial Transmission**: Commands are sent to the physical amplifier via USB serial
4. **Error Handling**: Failed commands are queued for retry with error recovery

### Serial Command Examples

- **Volume Control**: `VOL001` (set volume to 1%), `VOL100` (set volume to 100%)
- **Device Master**: `DMV080` (set device master volume to 80%)
- **Output Control**: `OUT145` (set output 1 volume to 45%)
- **Mute Control**: `MUT10` (mute output 1), `MUT00` (unmute output 1)
- **Power Control**: `PWR11` (power on output 1), `PWR10` (power off output 1)

### Configuration

Hardware controllers are configured in `lib/amp_bridge/hardware_manager.ex`:

```elixir
{AmpBridge.HardwareController, %{
  device_id: 1,
  name: "Main Amplifier",
  serial_port: "/dev/ttyUSB0",  # Adjust for your system
  baud_rate: 9600,
  data_bits: 8,
  stop_bits: 1,
  parity: :none
}}
```

### Future Expansion

The system is designed to support:
- **Multiple Amplifiers**: Each with its own controller and serial connection
- **Zone Management**: Control multiple speaker zones independently
- **Protocol Support**: RS232, RS485, TCP/IP, and other communication methods
- **Advanced Features**: DSP control, equalization, crossover settings

### Testing

Use the `test_hardware.exs` script to test the hardware management system:

```bash
elixir test_hardware.exs
```

This will start the hardware manager and show how it responds to device updates in real-time.

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

- **Audio Device Management**: Core logic for device communication
- **Zone Controller**: Zone state and configuration management
- **Protocol Handler**: Universal communication layer supporting multiple protocols and device types
- **MQTT Bridge**: Smart home integration service
- **Web Interface**: LiveView-based control panel

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

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on:

- Code style and standards
- Testing requirements
- Pull request process
- Development setup

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

For support and questions:

- **Documentation**: [docs.ampbridge.dev](https://docs.ampbridge.dev)
- **Issues**: [GitHub Issues](https://github.com/your-org/ampbridge/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-org/ampbridge/discussions)

## Roadmap

- [ ] Enhanced device discovery and auto-configuration
- [ ] Advanced automation rules engine
- [ ] Mobile application
- [ ] Cloud configuration sync
- [ ] Multi-site management
- [ ] Advanced analytics and reporting

---

**AmpBridge** - Bridging the gap between complex audio systems and modern control interfaces.
