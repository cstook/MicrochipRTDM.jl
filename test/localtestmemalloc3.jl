# test memory allocation

using MicrochipRTDM
using FTD2XX

projectdirectory = "c:/Users/Chris/MPLABXProjects/lbcmcp/PWM_RTDM.x"
mapdict = microchip_parsemap(projectdirectory,"production")
uartconfig1 = UARTConfiguration(921600,8,1,"n",readtimeout = 1000,writetimeout = 1000)
io = open(FT_DeviceIndex(0),uartconfig1)

const address = UInt32(mapdict["offsetP3"])
const buffer = [0x1234]
f() = for i in 1:100; rtdm_write(io, buffer, address); end
f()


Profile.clear_malloc_data()
f()

close(io)
quit()
