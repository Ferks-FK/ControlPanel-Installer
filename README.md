<h1 align=center>ControlPanel-Installer</h1>

![Discord](https://img.shields.io/discord/876934115302178876?label=DISCORD&style=for-the-badge)
![Contributors](https://img.shields.io/github/contributors/Ferks-FK/ControlPanel-Installer?style=for-the-badge)

This is an installation script for [ControlPanel](https://controlpanel.gg/)<br>
This script is not associated with the official project.

<h1 align="center">Features</h1>

- Automatic installation of the ControlPanel (dependencies, database, cronjob, nginx).
- Automatic configuration of UFW (firewall for Ubuntu/Debian).
- (Optional) automatic configuration of Let's Encrypt.
- (Optional) Automatic panel upgrade to a newer version.

<h1 align="center">Support</h1>

For help and support regarding the script itself and **not the official ControlPanel project**, Join our [Support Group](https://discord.gg/buDBbSGJmQ).

<h1 align=center>Supported installations</h1>

List of supported installation setups for panel (installations supported by this installation script).

<h1 align="center">Systems supported by script</h1></br>

|   Operating System    |  Version       | ✔️ \| ❌    |
| :---                  |     :---       | :---:      |
| Debian                | 9              | ✔️         |
|                       | 10             | ✔️         |
|                       | 11             | ✔️         |
| Ubuntu                | 18             | ✔️         |
|                       | 20             | ✔️         |
|                       | 22             | ✔️         |
| CentOS                | 7              | ✔️         |
|                       | 8              | ✔️         |


<h1 align="center">How to use</h1>

Just run the following command as root user.

```bash
bash <(curl -s https://raw.githubusercontent.com/Ferks-FK/ControlPanel-Installer/development/install.sh)
```

<h1 align="center">Attention!</h1>

*Do not run the command using sudo.*

**Example:** ```$ sudo bash <(curl -s...```

*You must be logged into your system as root to use the command.*

**Example:** ```# bash <(curl -s...```


<h1 align="center">Development</h1>

This script was created and is being maintained by [Ferks - FK](https://github.com/Ferks-FK).

<h1 align="center">Extra informations</h1>

If you have any ideas, or suggestions, feel free to say so in the [Support Group](https://discord.gg/buDBbSGJmQ).
