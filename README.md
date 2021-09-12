# Rivercarro

A slightly modified version of _rivertile_ layout generator for
**[river][]**

Compared to _rivertile_, _rivercarro_ add:

-   monocle layout
-   smart gaps
-   "true" inner gaps instead of padding around views

I don't want to add too much complexity, the only thing I intend
to add now is `smart borders`, after that I'll consider _rivercarro_
features complete. If you want a layout generator with more features
and configuration, have a look at some others great community
contributions like [stacktile][] or [kile][].

[river]: https://github.com/ifreund/river
[stacktile]: https://sr.ht/~leon_plickat/stacktile/
[kile]: https://gitlab.com/snakedye/kile

# Building

Same requirements as **[river][]**, use [zig 0.8.0][] too, if **[river][]** and
_rivertile_ works on your machine you shouldn't have any problems

Init submodules:

    git submodule update --init

Build, `e.g.`

    zig build --prefix ~/.local

[river]: https://github.com/ifreund/river#building
[zig 0.8.0]: https://ziglang.org/download/

# Usage

Works exactly as _rivertile_, you can just replace _rivertile_ name by
_rivercarro_ in your config, and read `rivertile(1)` man page

`e.g.` In your **river** init (usually `$XDG_CONFIG_HOME/river/init`)

```bash
# Mod+H and Mod+L to decrease/increase the main ratio of rivercarro
riverctl map normal $mod H send-layout-cmd rivercarro "main-ratio -0.05"
riverctl map normal $mod L send-layout-cmd rivercarro "main-ratio +0.05"

# Mod+Shift+H and Mod+Shift+L to increment/decrement the main count of rivercarro
riverctl map normal $mod+Shift H send-layout-cmd rivercarro "main-count +1"
riverctl map normal $mod+Shift L send-layout-cmd rivercarro "main-count -1"

# Mod+{Up,Right,Down,Left} to change layout orientation
riverctl map normal $mod Up    send-layout-cmd rivercarro "main-location top"
riverctl map normal $mod Right send-layout-cmd rivercarro "main-location right"
riverctl map normal $mod Down  send-layout-cmd rivercarro "main-location bottom"
riverctl map normal $mod Left  send-layout-cmd rivercarro "main-location left"
# And for monocle
riverctl map normal $mod M     send-layout-cmd rivercarro "main-location monocle"

# Set and exec into the default layout generator, rivercarro.
# River will send the process group of the init executable SIGTERM on exit.
riverctl default-layout rivercarro
exec rivercarro
```

## Command line options

```
$ rivercarro -help
Usage: rivercarro [options]

  -help           Print this help message and exit.
  -view-padding   Set the padding around views in pixels. (Default 6)
  -outer-padding  Set the padding around the edge of the layout area in
                  pixels. (Default 6)

  The following commands may also be sent to rivercarro at runtime:

  -main-location  Set the initial location of the main area in the
                  layout. (Default left)
  -main-count     Set the initial number of views in the main area of the
                  layout. (Default 1)
  -main-ratio     Set the initial ratio of main area to total layout
                  area. (Default: 0.6)
  -no-smart-gaps  Disable smart gaps
```

# Contributing

For patches, questions or discussion use [git send-email][] to send
a mail to my [public inbox][] [~novakane/public-inbox@lists.sr.ht][]
with project prefix set to `rivercarro`:

```
git config sendemail.to "~novakane/public-inbox@lists.sr.ht"
git config format.subjectPrefix "PATCH rivercarro"
```

Run `zig fmt` and wrap line at 100 columns unless it helps the
readability.

You can also found me on _IRC_ `irc.libera.chat` as `novakane`, mostly on
`#river`

[git send-email]: https://git-send-email.io
[public inbox]: https://lists.sr.ht/~novakane/public-inbox
[~novakane/public-inbox@lists.sr.ht]: mailto:~novakane/public-inbox@lists.sr.ht

# Thanks

Almost all credits go to [Isaac Freund][] and [Leon Henrik Plickat][]

**Thanks to them!**

[isaac freund]: https://github.com/ifreund
[leon henrik plickat]: https://sr.ht/~leon_plickat/

# License

[GNU General Public License v3.0][]

[gnu general public license v3.0]: LICENSE
