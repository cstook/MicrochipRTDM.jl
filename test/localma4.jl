using MicrochipRTDM
using FTD2XX

projectdirectory = "c:/Users/Chris/MPLABXProjects/lbcmcp/PWM_RTDM.x"
mapdict = microchip_parsemap(projectdirectory,"production")
uartconfig1 = UARTConfiguration(921600,8,1,"n",readtimeout = 1000,writetimeout = 1000)

const address = mapdict[:offsetP3]
const buffer = Array(UInt16,1)
const buffer2 = Array(UInt8,128)
const buffer3 = Array(UInt8,9)

function f()
  io = open(FT_DeviceIndex(0),uartconfig1)
  setlatencytimer(io,2); #Should speed things up a little
  rtdminterface = RTDMInterface(mapdict,io)
  for i in 1:100
    isrtdmok(rtdminterface)

    rtdm_read!(rtdminterface, buffer, address)
    x = rtdm_read(rtdminterface, UInt16, address)
    rtdm_read!(rtdminterface, buffer2, :SPI1CH1_BUFFER)

    rtdm_write(rtdminterface, buffer3, :SPI1CH1_BUFFER)
    rtdm_write(rtdminterface, 0x1234, :offsetP3)
  end
  close(rtdminterface)
  return nothing
end

f()

Profile.clear_malloc_data()
f()
quit()