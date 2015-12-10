# test memory allocation

using MicrochipRTDM
using FTD2XX

projectdirectory = "c:/Users/Chris/MPLABXProjects/lbcmcp/PWM_RTDM.x"
mapdict = microchip_parsemap(projectdirectory,"production")
uartconfig1 = UARTConfiguration(921600,8,1,"n",readtimeout = 1000,writetimeout = 1000)
io = open(FT_DeviceIndex(0),uartconfig1)
ft_setlatencytimer(io.ft_handle,2); #Should speed things up a little
rtdminterface = RTDMInterface(mapdict,io)

const address = mapdict["offsetP3"]
const buffer = Array(UInt16,1)
function f()
  for i in 1:1000
    rtdm_read!(rtdminterface, buffer, address)
    x = rtdm_read(rtdminterface, UInt16, address)
  end
end

f()

Profile.clear_malloc_data()
f()
#rtdm_read!(io, buffer, address)

close(io)
quit()