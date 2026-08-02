It's impossible to fully manage admin windows from a non-elevated ahk process
(at least, window position manipulation breaks, maybe some other significant things too).
My setup is roughly this:
- my main account: non-admin, no any special rights
- a secondary account: admin, I use it for running elevated processes

So on my system I can't normally autorun this whole thing without getting the UAC window on every
startup. And the autorun setup was kinda trash in general. This is why I've decided
to use a SYSTEM process that could invoke the script without all the inconvenience.

This is why I need that Setup.ps1 and the Launcher.ahk.

Why the launcher is in AHK? Simply cause bootstrapping a "normal" level process from SYSTEM requires
a lot of system interaction and DLL calling - PS would simply be too complicated for this.
And I don't wanna compile anything here so I haven't written it in C.

To put it simply, I want to control admin level windows. To control them - I need an elevated process.
And to run an elevated process on my system, I need a SYSTEM level task. And I can't *just run* AHK from SYSTEM - it will be broken in many ways.