using MicrochipRTDM
using FTD2XX
#=
38400
57600
115200
128000
224000
256000
460800
921600
=#
projectdirectory = "c:/Users/Chris/MPLABXProjects/lbcmcp/PWM_RTDM.x"
mapdict = microchip_parsemap(projectdirectory,"production")
uartconfig1 = UARTConfiguration(921600,8,1,"n",readtimeout = 1000,writetimeout = 1000)
io = open(FT_DeviceIndex(0),uartconfig1)
setlatencytimer(io,2); #Should speed things up a little
rtdminterface = RTDMInterface(mapdict,io)
const r = 1
const address = mapdict[:offsetP3]
const buffer = Array(UInt16,1)
const buffer2 = Array(UInt8,128)
const buffer3 = Array(UInt8,9)
i = 35

rtdm_write(rtdminterface, i, :DTRB, retry = r)

close(rtdminterface)
