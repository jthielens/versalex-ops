# cleo-service

Use this script to install Linux systemd or upstart services for Cleo VersaLex components.

## Usage

```
sudo cleo-service install (service|path) [alias]
sudo cleo-service remove service
```

Usage 1 installs and enables a service configuration file, depending on the init system in use on the platform.  For newer `systemd`-based systems:

- *alias*.service is installed in `/lib/systemd/system/`
- the service is enabled with `systemctl enable service`
- note that this action implicitly calls `systemctl daemon-reload`

For older `upstart`-based systems:

- an upstart conf *alias*.conf is installed in `/etc/init/`
- *alias* in `/etc/init.d/cleo-service` is linked to `upstart-job`
- `initctl reload-configuration` is called automatically.

Usage 2 removes the affected artifacts and reloads the inti configuration.

## Supported Services

The following services are supported:

| Install | Start |
|---------|-------|
| `cleo-service install cleo-harmony`  | `systemctl start cleo-harmony`  |
| `cleo-service install cleo-report`   | `systemctl start cleo-report`   |
| `cleo-service install cleo-vltrader` | `systemctl start cleo-vltrader` |
| `cleo-service install cleo-vlproxy`  | `systemctl start cleo-vlproxy`  |

Note that `initctl` must be used instead of `systemctl` on upstart-based systems.  Use `ps -p1` to determine the init process of your system if you are not sure.

Note also that you may provide either the service name (e.g. `cleo-harmony`), in which case the script will guess a few usual places for the installation directory, or the installation directory (e.g. `Harmony` or `$HOME/Harmony`), in which case the script will examine the contents of the directory to determine the service name.

You may also provide an optional alias to override the service name.  This could be used, for example, to run multiple services of the same type on a single machine.

## Permissions

It is not recommended to run Cleo VersaLex services as `root`.  The init configuration is generated with `User` and `Group` (or `setuid` and `setgid` for upstart) directives derived from the owner of the installation files.  The `cleo-service` script is, however, intended to be run under `sudo`.

## Bugs

The `ExecStartPost` and `ExecStop` (`post-start` and `pre-stop` for upstart) scripts for VLProxy are not yet correctly defined.

Upstart tested on Ubuntu 12.04 LTS and 14.04 LTS.

Systemd tested on Centos 7.0.