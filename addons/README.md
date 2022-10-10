# addons

Add-ons are ways to add extra features to file-browser, for example adding support for network file servers like ftp, or implementing virtual directories in the root like recently opened files.
They can be enabled by setting `addon` script-opt to yes, and placing the addon file into the `~~/script-modules/file-browser-addons/` directory.

Browsing filesystems provided by add-ons should feel identical to the normal handling of the script,
but they may require extra commandline tools be installed.

Since addons are loaded programatically from the addon directory it is possible for anyone to write their own addon.
Instructions on how to do this are available [here](addons.md).

For a list of available addons see the [wiki](https://github.com/CogentRedTester/mpv-file-browser/wiki/Addon-List).
