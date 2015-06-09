# cleo-service

Use this script to install Linux upstart services for Cleo VersaLex components.

## Usage

```
sudo cleo-service install (service|path) [alias]
sudo cleo-service remove service
```

Usage 1 installs an upstart conf file in `/etc/init/cleo-service.conf` and links `upstart-job` to `/etc/init.d/cleo-service` for a supported Cleo VersaLex service.  Usage 2 removes these artifacts.  In both cases, `initctl reload-configuration` is called automatically.

## Supported Services

The following services are supported:

| Install | Start |
|---------|-------|
| `cleo-service install cleo-harmony`  | `initctl start cleo-harmony`  |
| `cleo-service install cleo-report`   | `initctl start cleo-report`   |
| `cleo-service install cleo-vltrader` | `initctl start cleo-vltrader` |
| `cleo-service install cleo-vlproxy`  | `initctl start cleo-vlproxy`  |

Note that you may provide either the service name (e.g. `cleo-harmony`), in which case the script will guess a few usual places for the installation directory, or the installation directory (e.g. `Harmony` or `$HOME/Harmony`), in which case the script will examine the contents of the directory to determine the service name.

You may also provide an optional alias to override the service name.  This could be used, for example, to run multiple services of the same type on a single machine.

## Permissions

It is not recommended to run Cleo VersaLex services as `root`.  The upstart configuration is generated with `setuid` and `setgid` directives derived from the owner of the installation files.  The `cleo-service` script is, however, intended to be run under `sudo`.

## Bugs

The `post-start` and `pre-stop` scripts for VLProxy are not yet correctly defined.

Tested on Ubuntu 12.04 LTS "Precise Pangolin" so far.
