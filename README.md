# MicrochipRTDM.jl

[![Build Status](https://travis-ci.org/cstook/MicrochipRTDM.jl.svg?branch=master)](https://travis-ci.org/cstook/MicrochipRTDM.jl)

MichrochipRTDM.jl is a bunch of functions usefull for working with [Microchip's](http://www.microchip.com)<sup>TM</sup> [RTDM](http://ww1.microchip.com/downloads/en/DeviceDoc/70567A.pdf) interface in julia.

## Installation

MicrochipRTDM.jl is currently unregistered.  It can be installed using ```Pkg.clone```.
```julia
Pkg.clone("https://github.com/cstook/MicrochipRTDM.jl.git")
```
The [julia documentation](http://docs.julialang.org) section on installing unregistered [packages](http://docs.julialang.org/en/release-0.4/manual/packages/#packages) provides more information.

## Usage

Load the module.
```julia
using MicrochipRTDM
```

Create a dictionary of symbols from the .map file.
```julia
projectdirectory = "your_project_directory.x"
mapdict = microchip_parsemap(projectdirectory,"production")
```
The second parameter is either "production" or "debug".  It will default to "production" if unspecified.  You can pass the .map file instead of the project directory.  In this case the second parameter is ignored.

The following assumes a serial port is opened as io.  One way to do this is to use [FTD2XX.jl](https://github.com/cstook/FTD2XX.jl).

Create an ```RTDMInterface``` object.
```julia
rtdminterface = RTDMInterface(mapdict,io)
```

The RTDM link can be verifyed.
```julia
isrtdmok(rtdminterface)
```

The memory of the microcontroller can be read and written with ```rtdm_read```, ```rtdm_read!```, and ```rtdm_write```.
```julia
# read a single unsigned 16 bit integer
readvalue = rtdm_read(rtdminterface, UInt16, :your_symbol_name,retry = 3)

# read 128 unsigned 16 bit integers
bufffer = Array(UInt16,128)
rtdm_read!(rtdminterface, buffer, :your_symbol_name)

rtdm_write(rtdminterface, 0x1234, :your_symbol_name) # write 16 bit value
rtdm_write(rtdminterface, 0x12,   :your_symbol_name) # write 8 bit value)
rtdm_write(rtdminterface, buffer, :your_symbol_name) # write array
# need to increase default buffer size in microcontroller to write large arrays

# or just specify address as Integer
rtdm_write(rtdminterface, 0x1234, 0x00000100)
```

Close the interface.
```Julia
close(rtdminterface)
```
