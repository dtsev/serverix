<h3 align="center"><img src="misc/serverix.png" alt="serverix"><br>serverix - <i>build your minecraft server in semi-declarative way</i></h3>

## Usage
Usage of `serverix` is pretty simple and straightforward:
1. create a lua file that will be a configuration of your server
2. require serverix in it
```lua
local serverix = require("serverix") 
```
3. use `serverix.InitServer` method for configuring your server
```lua
serverix.InitServer( --initiate your server
    "my-server", --server name
    "paper", --server's core
    "1.20.1", --version
    BukkitPlugins, --plugins that should be installed
    nil, --mods is nil, because Paper only support plugins, so, if our server was fabric or forge, we've set BukkitPlugins as nil
    "/home/user/Desktop/server" --folder where your server will be installed
)
```
## Installation
### Prerequisites
- `lua 5.1`
- `luasec`
- `dkjson`
- `fzf`
- `sha1`
- `lfs`
- `lyaml`

> [!TIP]
> It's recommended to install `luasec`, `sha1`, `lfs`, `lyaml` and `dkjson` using `luarocks`, but if you install it **correctly** in other, it **should** work fine

```bash
luarocks install luasec
luarocks install dkjson
luarocks install sha1
git clone https://github.com/dtsev/serverix.git #clone this repo
cd serverix #cd into it
```
and repeat [usage](#usage) steps

## Credits
- <a href="https://www.freeiconspng.com/img/40686">Minecraft Server Icon Download Vectors Free</a>
- <a href="https://www.freeiconspng.com/img/26300">Snowflake PNG image</a>
