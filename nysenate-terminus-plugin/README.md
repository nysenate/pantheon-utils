NYSenate Terminus Plugin
========================

This is a simple plugin for Pantheon's Terminus command line interface that
extends its functionality for use at the New York State Senate.

Terminus is the main CLI utility offered by Pantheon to manage customer
sites and environments.  Since version 0.10.3, Terminus supports the use
of plugins to extend its functionality.

Requirements
------------
This plugin will work with versions of Terminus that are prior to 1.0, such
as 0.10.x through 0.13.x.

For Terminus 1.0 and above, the terminus-replica-plugin repo should be used.
It can be found at:
https://github.com/terminus-plugin-project/terminus-replica-plugin

Installation
------------
To install this plugin, move the entire `nysenate-terminus-plugin`
directory into `$HOME/terminus/plugins/`, or set the `TERMINUS_PLUGINS_DIR`
environment variable to point to the correct directory.

This command can be invoked by running:
```
terminus site replica-info [options]
```

Use `terminus help site` for a listing of all 'site' subcommands.
Use `terminus help site replica-info` for help on the 'replica-info' command.
Use `terminus site` for a full usage message for the 'site' command.

Warning
-------
DISCLAIMER!!!  Connecting to replica databases should only be done by those
who know what they are doing.  Writing to a replica database is highly
ill-advised, since the master database overwrites the replica and the risk
of data corruption is elevated.  In addition, Pantheon connection strings
change frequently due to endpoint migrations and such.  As a result, live
connections to the replica database will sometimes fail until the latest
connection string is retrieved.

Author
------
Ken Zalewski (zalewski@nysenate.gov)

Further Reading
---------------
Learn more about Terminus and Terminus Plugins at:
[https://github.com/pantheon-systems/cli/wiki/Plugins](https://github.com/pantheon-systems/cli/wiki/Plugins)
