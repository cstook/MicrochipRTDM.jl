# compute running crc for microchip RTDM
# pass crc = 0xffff to start
const polynomial = 0xa001
function rtdm_crc(crc::UInt16, data::UInt8)
  for i in 1:8
    if ((crc $ data)&0x0001) == 0x0001
      crc = (crc>>>1) $ polynomial
    else
      crc = crc>>>1
    end
    data >>>=1
  end
  return crc
end

pipecrc = PipeBuffer()
const buffercrc = Array(UInt8,1)
function rtdm_crc(crc::UInt16, data)
  write(pipecrc,data)
  while ~eof(pipecrc)
    buffercrc[1] = read(pipecrc, UInt8)
    crc = rtdm_crc(crc, buffercrc[1])
  end
  return crc
end

function rtdm_crc(crc::UInt16, data::Array{Any})
  for element in data
    crc = rtdm_crc(crc, element)
  end
  return crc
end

rtdm_crc(data) = rtdm_crc(0xffff,data)  # or call with one parameter to start
