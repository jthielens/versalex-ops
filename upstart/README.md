# cleo-service

Use this script to install Linux upstart services for Cleo VersaLex components.

## Usage

```
sudo cleo-service install service [path]
sudo cleo-service remove service
```

Usage 1 installs an upstart conf file in `/etc/init/cleo-service.conf` and links `upstart-job` to `/etc/init.d/cleo-service` for a supported Cleo VersaLex service.  Usage 2 removes these artifacts.  In both cases, `initctl reload-configuration` is called automatically.

## Supported Services

The following services are supported:

| Install | Start |
|---------|-------|
| `cleo-service install harmony`  | `initctl start cleo-harmony`  |
| `cleo-service install report`   | `initctl start cleo-report`   |
| `cleo-service install vltrader` | `initctl start cleo-vltrader` |
| `cleo-service install vlproxy`  | `initctl start cleo-vlproxy`  |

## Permissions

It is not recommended to run Cleo VersaLex services as `root`.  The upstart configuration is generated with `setuid` and `setgid` directives derived from the owner of the installation files.  The `cleo-service` script is, however, intended to be run under `sudo`.

## Bugs

The `post-start` and `pre-stop` scripts for VLProxy are not yet correctly defined.

Tested on Ubuntu 12.04 LTS "Precise Pangolin" so far.
