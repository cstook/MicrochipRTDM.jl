# test memory allocation

using MicrochipRTDM
using FTD2XX

projectdirectory = "c:/Users/Chris/MPLABXProjects/lbcmcp/PWM_RTDM.x"
mapdict = microchip_parsemap(projectdirectory,"production")
uartconfig1 = UARTConfiguration(921600,8,1,"n",readtimeout = 1000,writetimeout = 1000)
io = open(FT_DeviceIndex(0),uartconfig1)
setlatencytimer(io,2); #Should speed things up a little
rtdminterface = RTDMInterface(mapdict,io)


const address = UInt32(mapdict[:offsetP3])
const buffer = [0x1234]
function f()
  for i in 1:1000
    #rtdm_write(rtdminterface, buffer, address)
    rtdm_write(rtdminterface, 0x1234, address)
  end
  return nothing
end
f()


Profile.clear_malloc_data()
f()


close(rtdminterface)
quit()
