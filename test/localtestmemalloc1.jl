# test memory allocation

using MicrochipRTDM
using FTD2XX

projectdirectory = "c:/Users/Chris/MPLABXProjects/lbcmcp/PWM_RTDM.x"
mapdict = microchip_parsemap(projectdirectory,"production")
uartconfig1 = UARTConfiguration(921600,8,1,"n",readtimeout = 1000,writetimeout = 1000)
io = open(FT_DeviceIndex(0),uartconfig1)

rtdminterface = RTDMInterface(mapdict,io)

f() = for i in 1:100; isrtdmok(rtdminterface); end
@time f()


Profile.clear_malloc_data()
f()

close(io)
quit()
