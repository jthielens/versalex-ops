versalex-ops
============

This is a collection of DevOps style tools for Cleo VersaLex products.

## upstart

A Linux shell script for managing Cleo components in an upstart-based init toolchain.

## logstash

A Ruby (because that is how it works with LogStash) script for following a VersaLex XML log
in a one-event-per-line format reminiscent of `tail -f`, plus a LogStash input plugin that uses
this script as a module.
