export rtdm_write, rtdm_read, rtdm_read!, isrtdmok

const ENDIAN_BOM = reinterpret(UInt32,UInt8[1:4;])[1]
fixendian(x) = ENDIAN_BOM==0x04030201?x:bswap(x)

### BEGIN function to compute CRC
function rtdm_crc(data :: Array{UInt8,1})
  const polynomial = 0xa001
  crc = 0xffff
  for byte in data
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
### END function to compute CRC

### BEGIN functions to create RTDM commands and parse replys
function rtdm_createreadcommand(start, bytes)
  command = Array(UInt8,11)
  command[1] = 0x24 # start code "$"
  command[2] = 0x6d # function code "m"
  command[3:6] = reinterpret(UInt8,[fixendian(convert(UInt32,start))]) # start address
  command[7:8] = reinterpret(UInt8,[fixendian(convert(UInt16,bytes))]) # number of bytes to transfer
  command[9] = 0x23 # end of message code "#"
  command[10:11] = reinterpret(UInt8,[fixendian(rtdm_crc(command[1:9]))]) # CRC in little endian
  return command
end
function rtdm_parsereadreply(reply::Array{UInt8,1})
  if reply[1] == 0x2d # "-" is error code
    error("target replies with error code ",ASCIIString(reply[3:5]))
  end
  if reply[1] != 0x2b # did not get "+" reply code
    error("missing \"+\" reply code")
  end
  if reply[2] != 0x24 # did not get "$" start code
    error("missing \"\$\" start code")
  end
  numberofdatabytes = length(reply) - 5
  if numberofdatabytes < 1
    error("reply is too short")
  end
  data = reply[3:numberofdatabytes+2] # the data we want
  if reply[numberofdatabytes+3] != 0x23 # did not receive "#" end of message code
    error("missing \"#\" end of message code")
  end
  crc = reinterpret(UInt8,[fixendian(rtdm_crc(reply[1:end-2]))]) # CRC in little endian
  if crc != reply[end-1:end] # crc failed
    error("crc check failed")
  end
  return data
end
function rtdm_createwritecommand(start, data::Array{UInt8,1})
  commandlength = length(data) + 11
  command = Array(UInt8,commandlength)
  command[1] = 0x24 # start code "$"
  command[2] = 0x4d # function code "M"
  command[3:6] = reinterpret(UInt8,[fixendian(convert(UInt32,start))]) # start address
  command[7:8] = reinterpret(UInt8,[fixendian(convert(UInt16, length(data)))]) # number of bytes to transfer
  command[9:length(data)+8] = data
  command[end-2] = 0x23 # end of message "#"
  command[end-1:end] = reinterpret(UInt8,[fixendian(rtdm_crc(command[1:end-2]))]) # CRC in little endian
  return command
end
function rtdm_parsewritereply(reply::Array{UInt8,1})
  if reply[1] == 0x2d # "-" is error code
    error("target replies with error code ",ASCIIString(reply[3:5]))
  end
  if reply[1] != 0x2b # did not get "+" reply code
    error("missing \"+\" reply code")
  end
  if reply[2] != 0x24 # did not get "$" start code
    error("missing \"\$\" start code")
  end
  if reply[3:4] != [0x4f, 0x4b] # did not receive "OK"
    error("missing \"OK\"")
  end
  if reply[5] != 0x23 # did not receive "#" end of message code
    error("missing \"#\" end of message code")
  end
  if reply[6:7] != (ENDIAN_BOM == 0x04030201?[0x4c, 0x08]:[0x08, 0x4c])  # crc failed
    error("crc failed")
  end
  return nothing
end
const rtdm_sanitycheckcommand = (ENDIAN_BOM == 0x04030201?[0x24, 0x73, 0x23, 0x55, 0x22]:[0x24, 0x73, 0x23, 0x22, 0x55])
function rtdm_parsesanitycheckreply(reply::Array{UInt8,1})
  const SCmessage = [0x2b, 0x24, 0x52, 0x54, 0x44, 0x4d, 0x23]
  const SCcrc = reinterpret(UInt8,[finendian(rtdm_crc(SCmessage))]) # CRC in little endian
  const SCreply = [SCmessage;SCcrc]
  if reply[1] == '-'
    error("target replied with error code ",reply[3:5])
  elseif reply != SCreply
    error("invalid response")
  end
  return nothing
end
### END functions to create RTDM commands and parse replys

### BEGIN other RTDM functions
function isrtdmok(io::IO)
  byteswritten = write(io,rtdm_sanitycheckcommand)
  const replyok = (ENDIAN_BOM == 0x04030201?[0x2b, 0x24, 0x52, 0x54, 0x44, 0x4d, 0x23, 0x1b, 0x86]:[0x2b, 0x24, 0x52, 0x54, 0x44, 0x4d, 0x23, 0x86, 0x1b])
  reply = Array(UInt8,length(replyok))
  read!(io,reply)
  return reply == replyok
end
function rtdm_write(io::IO,value::Number, address::Integer)
  # writefunction(buffer :: Array{UInt8,1}) --> Int
  # writes buffer to microcontroler, retruns number of bytes written
  # readfunction!(buffer :: Array{UInt8,1}) --> Int
  # reads from microcontroler to fill array, retruns number of bytes read
  data = reinterpret(UInt8,[fixendian(value)])
  command = rtdm_createwritecommand(address,data)
  byteswritten = write(io,command)
  @assert byteswritten == length(command)
  reply = Array(UInt8,7)
  read!(io,reply)
  rtdm_parsewritereply(reply)
  return nothing
end
function rtdm_write{T<:Number}(io::IO, buffer::Array{T,1}, address::Integer)
  bytelength = length(buffer)*sizeof(T)
  bytearray = Array(UInt8,bytelength) # This is not efficent, but I am to lazy to rewrite now.
  for (i,element) in enumerate(buffer)
    bytearray[i:i+sizeof(T)-1] = fixendian(reinterpret(UInt8,[element]))
  end
  command = rtdm_createwritecommand(address,bytearray)
  byteswritten = write(io,command)
  @assert byteswritten == length(command)
  reply = Array(UInt8,7)
  read!(io,reply)
  rtdm_parsewritereply(reply)
  return nothing
end
function rtdm_read{T<:Number}(io::IO, ::Type{T}, address::Integer)
  command = rtdm_createreadcommand(address,sizeof(T))
  byteswritten = write(io,command)
  @assert byteswritten == length(command)
  reply = Array(UInt8,5+sizeof(T))
  read!(io,reply)
  replyvaluebytearray = rtdm_parsereadreply(reply)
  value = fixendian(reinterpret(T,replyvaluebytearray)[1])
  return value
end
function rtdm_read!{T<:Number}(io::IO, buffer::Array{T,1}, address::Integer)
  bytelength = length(buffer)*sizeof(T)
  command = rtdm_createreadcommand(address, bytelength)
  byteswritten = write(io,command)
  @assert byteswritten == length(command)
  reply = Array(UInt8,bytelength+5)
  read!(io,reply)
  replyvaluebytearray = rtdm_parsereadreply(reply)
  for i in 1:length(buffer)
    buffer[i] = fixendian(reinterpret(T,replyvaluebytearray[i*2-1:i*2+sizeof(T)-2])[1])
  end
  return nothing
end