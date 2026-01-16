# A fun zig manager built with zig

While there are other great options for zig installation management, I wanted something that aligned more with workflows I was used to coming from the Node world, like [nvm](https://github.com/nvm-sh/nvm) and [fnm](https://github.com/Schniz/fnm), while learning Zig. Particularly I wanted more fine-grained ability to download and control versions, but also auto switching and env management built in.

## Installation

For now, installation is manual. You'll need to build from source and install it:

```sh
zig build install -Doptimize=ReleaseFast --prefix $HOME/.local
```

Ensure `$HOME/.local/bin` is in your `$PATH`.

## Shell Configuration

Right now, fzm only supports ZSH. Other shells might be added in the future.

### ZSH

Add the following to your `~/.zshrc`:

```sh
eval "$(fzm env)"
```

## Usage

### Installing a version of Zig

```sh
fzm install 0.15.2 # or master, 0.15.0, etc.
```

### Manually switching versions

```sh
fzm use 0.15.2 # or master, 0.15.0, etc.
```

### Automatically switching versions

Ensure your project has a `build.zig.zon` that specifies a `minimum_zig_version`. `fzm` will then use this to automatically switch to the highest version you have installed
that matches when you cd into the project.
