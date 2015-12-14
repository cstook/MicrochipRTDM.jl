#=
isrtdmok

reset crc

load pipe with data to write, any type
unload pipe to uart with crc

load pipe with bytes from uart, calculating running crc
load pipe with bytes from uart, no crc update
unload pipe to read data, any type
=#

# interface to rest of module is with iopipe not iopipe2

function sendpipewithcrc(i::RTDMinterface)  # always attach and send crc
  while ~eof(i.iopipe)
    byte = read(i.iopipe, UInt8)
    write(i.iopipe2, byte)
    i.crc.data = byte
    compute_crc(i.crc)
  end
  write(i.iopipe2, i.crc.crc)
  write(i.iouart, takebuf_array(i.iopipe2))
  resetcrc!(i)
end

function loadpipe(i::RTDMinterface, bytestoload::Integer, last2crc = bytestoload>1)
  # set last2crc = true to not include last two bytes read in crc calculation
  data = read(i.iouart, UInt8, bytestoread)
  for (index, element) in enumerate(data)
    if element < bytestoread-1
      i.crc.data = element
      compute_crc(i.crc)
    end
    write(i.iopipe,data)
  end
end
