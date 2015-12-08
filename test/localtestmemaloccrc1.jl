# localtestmemaloccrc1.jl
using MicrochipRTDM
using FTD2XX

projectdirectory = "c:/Users/Chris/MPLABXProjects/lbcmcp/PWM_RTDM.x"
mapdict = microchip_parsemap(projectdirectory,"production")
uartconfig1 = UARTConfiguration(921600,8,1,"n",readtimeout = 1000,writetimeout = 1000)
io = open(FT_DeviceIndex(0),uartconfig1)

const x = zeros(UInt64,10)
const buffer = Array(UInt8,1)
function f()
  i = UInt8(0)
  crc = MicrochipRTDM.rtdm_crc(0xffff,i)
  for i::UInt8 in 1:255
    crc = MicrochipRTDM.rtdm_crc(crc,x)
  end
end

g() = for i in 1:1000; f(); end
g()

Profile.clear_malloc_data()
g()

close(io)
quit()

