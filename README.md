# Injector

A simple tool to dynamically inject scripts into DCS missions

## Security considerations

Because this tool requires the mission environment to be desantized (more on that later on), you open yourself up to some risks. When installing 3rd party injector modules or running 3rd party missions, please ensure that they only come from a trusted source and are free from any dangerous code. The modules that are sanitized by default, if desanitized, allow a nefarious actor among other things, to modify, delete and create files on your filesystem and execute shell commands at will.

## Installation

1. Get the latest release from the release section. 
1. Drop the file `injector.lua` into your DCS saved games directory under `C:\Users\<Your Name>\Saved Games\DCS(.openbeta)\Scripts\Hooks`. 
1. Desanitize the `Scripts\MissionScripting.lua` file in the DCS installation directory.

### Desanitation

By default the end of the file should look something like this:

```lua
do
	sanitizeModule('os')
	sanitizeModule('io')
	sanitizeModule('lfs')
	_G['require'] = nil
	_G['loadlib'] = nil
	_G['package'] = nil
end
```

To remove the sanitation, comment out or delete the entire do-end block:

```lua
-- do
-- 	sanitizeModule('os')
-- 	sanitizeModule('io')
-- 	sanitizeModule('lfs')
-- 	_G['require'] = nil
-- 	_G['loadlib'] = nil
-- 	_G['package'] = nil
-- end
```

## Creating injectable scripts

The injectable scripts are located in the DCS saved games directory under `Scripts\Inject`. Here every subfolder is treated as an injector module. The name of the subfolder is also the name of the module. A module consists of two files, both of which are optional and are loaded and executed when a mission in DCS starts. So DCS does not have to be restarted for every change to a script file. A restart of the current mission is sufficient.

1. `init.lua`: executed in the `mission` environment. All mission scripting functions are available just like in a `DO FILE` trigger action.
2. `hook.lua`: executed in the `gui` environment. This is a special environment where the hooks in `Scripts\Hooks` are executed in. The DCS installation directory contains a file (`API\DCS_ControlAPI.html`) with an incomplete list of the available API. For example: By using the `net.dostring_in` function you can pass data to the mission environment.

You are not limited to only these two files. By using the `require` function additional files can be loaded. Even modules external to your injector module can be imported. Note, that the injected scripts are executed inside of a sandbox, so multiple injector modules cannot interfere with each other. They are completely independent of each other and can not depend on each other either.

Check out [this project](https://github.com/Serious-Uglies/LiveMap) for an comprehensive example of how to use injector. Also a very simple example of an injector module can be found in this repository.