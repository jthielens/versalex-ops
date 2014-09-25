versalex-logstash
=================

Log tailer for Cleo Harmony and Cleo VLTrader (collectively "VersaLex") including a LogStash input plugin.

## Tailing the XML log

Harmony and VLTrader produce an XML log file in `logs/Harmony.xml` or `log/VLTrader.xml`, depending on the product.  This log file is maintained as a complete valid XML file, so each time it is updated, the proper closing tags (usually `</Run></Session></Log>`) are appended.  The next time an event is written to the log, the closing tags are overwritten, new `<Event>...</Event>`(s) are written to the log, and the XML elements are again properly closed.  This makes the log file impossible to `tail` using traditional tools.

## Input plugin for LogStash

As interesting as it is to be able to tail the XML log as if it were a typical flat file log, the real goal of the project is to create a LogStash input plugin that preserves the richness of the XML detail within the LogStash filter/output framework.
