# saystop

A floating **stop button** for macOS `say` speech output.

`say` is a great built-in TTS command, but once it starts talking there is no
built-in way to shut it up from the GUI. `saystop` runs `say` and shows a small,
always-on-top **Stop Speaking** panel near the top of your screen for as long as
speech is playing. Click the button or close the panel to kill the speech
immediately. The panel never steals keyboard focus.

It is especially handy when scripts, agents, or voice-output rules call `say`
unattended and you want a kill switch.

## Requirements

- macOS 12.0+ (Apple Silicon and Intel, universal binary)
- No other dependencies: it wraps `/usr/bin/say`

## Install

### Homebrew (tap)

```sh
brew install DevArtsLab/tap/saystop
```

### curl installer

```sh
curl -fsSL https://raw.githubusercontent.com/DevArtsLab/saystop/main/install.sh | sh
```

The release binary is unsigned, so the installer clears the quarantine
attribute after verifying the SHA-256 checksum. Options via env vars:
`SAYSTOP_VERSION`, `SAYSTOP_PREFIX`, `SAYSTOP_SHIM=1`.

### From source

```sh
git clone https://github.com/DevArtsLab/saystop.git
cd saystop
make          # universal binary in build/saystop
make install  # copies to /opt/homebrew/bin, /usr/local/bin, or ~/.local/bin
```

## Usage

```sh
saystop "Hello, I have a stop button now"
```

All arguments are passed through to `say`, so `-v`, `-f`, `-r`, etc. all work.
Invocations that produce no audible speech (`-o`, `-v ?`) skip the panel.

### Give every `say` call the button (optional shim)

```sh
saystop --install-shim
```

This writes a tiny `say` shell shim into the first writable PATH directory that
precedes `/usr/bin` (usually `/opt/homebrew/bin` or `/usr/local/bin`). After
that, plain `say "..."` from any terminal, script, or agent pops the stop
button. It never overwrites an existing `say` file that is not a saystop shim.

```sh
saystop --shim-status     # check
saystop --uninstall-shim  # remove
/usr/bin/say "..."        # always bypasses the shim
```

### Quick Action kill switch

`extras/Stop Speaking.workflow` is a macOS Quick Action that runs
`killall say`. Install it to get a menu-bar kill switch plus an assignable
global hotkey:

```sh
cp -R "extras/Stop Speaking.workflow" ~/Library/Services/
/System/Library/CoreServices/pbs -flush
```

Then find it under any app's **App Name > Services** menu, or bind a hotkey in
System Settings > Keyboard > Keyboard Shortcuts > Services.

## How it works

`saystop` spawns `/usr/bin/say` as a child process and displays a non-activating
floating `NSPanel`. The panel closes itself when the child exits (including when
speech ends naturally or the process is killed). Clicking **Stop Speaking** or
closing the window terminates the child.

## Uninstall

```sh
saystop --uninstall-shim
brew uninstall saystop        # or: rm the saystop binary from your bin dir
```

## License

MIT
