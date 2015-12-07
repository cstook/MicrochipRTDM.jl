# compute running crc for microchip RTDM
# pass crc = 0xffff to start

function rtdm_crc{T}(crc::UInt16, dataarray::Array{T})
  const polynomial = 0xa001
  databytearray = reinterpret(UInt8,dataarray)
  for byte in databytearray
    for i in 1:8
      if ((crc $ byte)&0x0001) == 0x0001
        crc = (crc>>>1) $ polynomial
      else
        crc = crc>>>1
      end
      byte >>>=1
    end
  end
  return crc
end

rtdm_crc(data) = rtdm_crc(0xffff,data)
rtdm_crc(crc::UInt16, data) = rtdm_crc(crc,[data])